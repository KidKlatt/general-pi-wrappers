/*
 * d3d9lazy - a tiny d3d9.dll shim for Medieval: Total War on tile-based GPUs.
 *
 * The game locks its whole off-screen render target for read/write CPU access after
 * every small 3D batch (about 18 times per frame). Each such lock forces WineD3D to
 * flush the GPU, read the full frame back and later upload it again.
 *
 * This shim forwards Direct3DCreate9 to the real d3d9.dll and patches LockRect and
 * UnlockRect in the IDirect3DSurface9 vtable. A full-surface, non-read-only LockRect
 * on a 16-bit render target is not passed on. The game gets a shim-owned overlay
 * buffer filled with a key colour instead. On UnlockRect the shim finds the pixels
 * the game changed and, if there are any, draws just that rectangle over the render
 * target on the GPU with the key colour transparent. No frame is ever read back.
 *
 * Known limits: pixels the game READS from the locked surface are the key colour, not
 * the rendered frame; a pixel the game deliberately draws in the exact key colour is
 * dropped. (Page-fault based lazy locking was tried first and cannot work under
 * Hangover/WowBox64: access faults in emulated code are retried forever.)
 *
 * Draw batching: the game issues about 790 DrawPrimitiveUP / DrawIndexedPrimitiveUP calls
 * per frame, mostly one- or two-triangle fans, and only about 45 times per frame does any
 * other device call come between two of them. Every draw costs a full trip through the
 * emulated WineD3D draw path. The shim therefore collects consecutive triangle draws
 * (lists, strips, fans; indexed or not; same vertex stride) into one indexed triangle
 * list and submits it when anything else happens: every other IDirect3DDevice9 method,
 * and LockRect on surfaces and textures, first run flush_batch() through a small
 * generated thunk. Draw order is unchanged. Limit: with flat shading the colour-giving
 * vertex of a converted fan or strip triangle may differ (the game uses Gouraud).
 *
 * An earlier attempt to submit each batch from its own DISCARD-locked dynamic buffers was
 * slower (6.4 against 11.7 FPS: every DISCARD allocates and copies a whole new buffer). The
 * grouped uploads further down lock a plain dynamic buffer once for many draws instead.
 *
 * Deferred overlays: a battle frame is one big world scene followed by about 16 tiny
 * scenes, each drawing one toolbar button background and each followed by a lock in
 * which the game paints that button's icon. Instead of answering every lock with its own
 * texture upload, state switch and draw, the changed pixels are moved to a pending
 * buffer and drawn together: rectangles that overlap vertically are merged into bands,
 * each band is one texture and one quad, all under a single state save/restore. Pending
 * overlays are drawn before anything that consumes or redirects the render target
 * (StretchRect, Present, SetRenderTarget, Clear, real surface locks, ...) and before any
 * draw whose screen-space bounding box touches a pending rectangle, so the visible order
 * of overlapping pixels is unchanged. D3D9LAZY_DEFER=0 draws each overlay at its unlock.
 *
 * Environment: D3D9LAZY=0      pass-through (shim loaded but inactive)
 *              D3D9LAZY_BATCH=0  no draw batching
 *              D3D9LAZY_FILTER=0  pass redundant state calls through
 *              D3D9LAZY_THREAD=0  play recorded calls at once on the game thread
 *              D3D9LAZY_DEFER=0  draw every overlay at its unlock
 *              D3D9LAZY_VB=0   keep user-pointer draws on the helper thread (no grouped uploads)
 *              D3D9LAZY_DEPTH=n  depth read-back copy refreshed every n-th frame (default 1; 0 = real locks)
 *              D3D9LAZY=probe  overlay is discarded, only statistics are kept
 *              D3D9LAZY_LOG=1  append statistics to d3d9lazy.log
 *
 * Build: i686-w64-mingw32-gcc -O2 -msse2 -shared -o d3d9.dll d3d9lazy.c -Wl,--kill-at -static-libgcc
 */
#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

#define MAX_SURF 8
#define MAX_PEND 32
#define KEY16 0x0020u           /* a near-black the game is unlikely to draw; blended edges stay dark */
#define KEY32 0x00200020u

struct lazy_surf
{
    IDirect3DSurface9 *iface;
    IDirect3DDevice9 *device;       /* not referenced */
    UINT width, height;
    BYTE *buf;
    BYTE *pbuf;                     /* pending overlay pixels, key colour elsewhere */
    RECT pend[MAX_PEND];
    UINT n_pend;
    SIZE_T size;
    INT pitch;
    BOOL locked;
    BOOL clean;                     /* buf is entirely key colour */
};

static struct lazy_surf surfs[MAX_SURF];
static CRITICAL_SECTION cs;
static HMODULE real_d3d9;
static IDirect3D9 *(WINAPI *real_create9)(UINT);
static HRESULT (WINAPI *real_create_device)(IDirect3D9 *, UINT, D3DDEVTYPE, HWND, DWORD,
        D3DPRESENT_PARAMETERS *, IDirect3DDevice9 **);
static HRESULT (WINAPI *real_lock)(IDirect3DSurface9 *, D3DLOCKED_RECT *, const RECT *, DWORD);
static HRESULT (WINAPI *real_unlock)(IDirect3DSurface9 *);
/* Created with the device, before the game uses up WineD3D's video memory budget. */
/* A pool of overlay textures in three sizes, used round-robin so that a texture is
 * never re-uploaded while a draw of the same frame still refers to it (on a tile-based
 * GPU that would force a flush). */
#define OVERLAY_SIZE 1024
#define POOL_CLASSES 7
#define POOL_MAX 32
/* WineD3D uploads the whole texture on every lock, so the classes are ordered by area and
 * fit the shapes seen in battle: one button (34x34), the minimap (120x120), the toolbar strip
 * (718x34), the cursor/tooltip block (132x224), the unit-card strip (532x66), anything. A
 * strip that fell through to the 1024x1024 class cost a 4 MB upload per frame. */
static const UINT pool_w[POOL_CLASSES] = {64, 128, 1024, 256, 1024, 512, OVERLAY_SIZE};
static const UINT pool_h[POOL_CLASSES] = {64, 128, 64, 256, 128, 512, OVERLAY_SIZE};
static const UINT pool_count[POOL_CLASSES] = {32, 8, 4, 6, 4, 2, 2};
static IDirect3DTexture9 *pool[POOL_CLASSES][POOL_MAX];
static UINT pool_next[POOL_CLASSES];
static BOOL pool_ready;
static enum { MODE_OFF, MODE_PROBE, MODE_OVERLAY } mode = MODE_OVERLAY;
static BOOL logging;
static BOOL deferring = TRUE;
static LONG n_emits, n_bands, n_early;
static DWORD key_row[OVERLAY_SIZE / 2];
static LONG n_windows, n_written, n_pass, n_fail;
static LONGLONG n_pixels;

/* Draw batching. */
#define BATCH_MAX_VERTS 32768
#define BATCH_MAX_IDX 131072
#define BATCH_MAX_STRIDE 64
static BOOL batching = TRUE;
static IDirect3DDevice9 *batch_dev;
static BYTE *batch_verts;
static WORD *batch_idx;
static UINT batch_nverts, batch_nidx, batch_stride;
static LONG n_draws_in, n_draws_out, n_draws_pass;
static HRESULT (WINAPI *real_dpup)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, const void *, UINT);
static HRESULT (WINAPI *real_dipup)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, UINT, UINT, const void *,
        D3DFORMAT, const void *, UINT);
static HRESULT (WINAPI *real_reset)(IDirect3DDevice9 *, D3DPRESENT_PARAMETERS *);
static HRESULT (WINAPI *real_get_fvf)(IDirect3DDevice9 *, DWORD *);
static void check_draw_against_pending(IDirect3DDevice9 *dev, const void *verts, UINT nv, UINT stride);
static void __cdecl emit_all(void);
static void shadow_forget(void);
static void emit_record(void);
static HRESULT (WINAPI *real_set_stream)(IDirect3DDevice9 *, UINT, IDirect3DVertexBuffer9 *, UINT, UINT);
static HRESULT (WINAPI *real_dp)(IDirect3DDevice9 *, D3DPRIMITIVETYPE, UINT, UINT);
static HRESULT (WINAPI *real_create_vb)(IDirect3DDevice9 *, UINT, DWORD, DWORD, D3DPOOL,
        IDirect3DVertexBuffer9 **, HANDLE *);
static HRESULT (WINAPI *real_begin)(IDirect3DDevice9 *);
static HRESULT (WINAPI *real_end)(IDirect3DDevice9 *);
static HRESULT (WINAPI *real_set_ds)(IDirect3DDevice9 *, IDirect3DSurface9 *);
static HRESULT (WINAPI *real_stretch)(IDirect3DDevice9 *, IDirect3DSurface9 *, const RECT *, IDirect3DSurface9 *,
        const RECT *, D3DTEXTUREFILTERTYPE);
static HRESULT (WINAPI *real_present)(IDirect3DDevice9 *, const RECT *, const RECT *, HWND, const RGNDATA *);
static HRESULT (WINAPI *real_get_bb)(IDirect3DDevice9 *, UINT, UINT, D3DBACKBUFFER_TYPE, IDirect3DSurface9 **);
static HRESULT (WINAPI *real_get_tss)(IDirect3DDevice9 *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD *);

static void log_line(const char *fmt, ...)
{
    char buf[512];
    DWORD written;
    HANDLE f;
    va_list ap;

    if (!logging)
        return;
    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    f = CreateFileA("d3d9lazy.log", FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, 0, NULL);
    if (f == INVALID_HANDLE_VALUE)
        return;
    WriteFile(f, buf, strlen(buf), &written, NULL);
    CloseHandle(f);
}

/* Dip recorder. While a file d3d9lazy.dips exists in the game directory, the time between
 * consecutive entries into the shim on the game thread is measured. A gap of 15 ms or more is
 * remembered as "from id -> to id"; when a frame takes 100 ms or more, its gaps are logged.
 * Ids: 0..118 device vtable slot (through a thunk), 120 texture LockRect, 200 DrawPrimitiveUP,
 * 201 DrawIndexedPrimitiveUP, 202 SetRenderState, 203 SetTexture, 204 SetTextureStageState,
 * 205 SetSamplerState, 206 SetFVF, 207 BeginScene, 208 EndScene, 209 SetDepthStencilSurface,
 * 210 StretchRect, 211 Present, 212 GetBackBuffer, 213 GetTextureStageState, 214 surface
 * LockRect, 216 surface UnlockRect; 1000 + id: the wait for the queue to drain before call id
 * has ended (so "5 -> 1005" is that wait, "1005 -> x" the call itself plus game code);
 * 1211: the wait for the previous frame's Present has ended. The helper thread logs any
 * command that takes 40 ms or more. Times are milliseconds since the shim was loaded. */
#define MAX_GAPS 10
static volatile BOOL dips_on;
static LARGE_INTEGER qpc_freq, qpc_start;
static DWORD mark_last_t, mark_frame_t;
static UINT mark_last_id, n_gaps, n_frames_seen;
static UINT n_band_log;
static struct { WORD from, to; DWORD ms; } gaps[MAX_GAPS];

static DWORD now_us(void)
{
    LARGE_INTEGER c;

    QueryPerformanceCounter(&c);
    return (DWORD)((c.QuadPart - qpc_start.QuadPart) * 1000000 / qpc_freq.QuadPart);
}

static void mark(UINT id)
{
    DWORD t, dt;

    if (!dips_on)
        return;
    t = now_us();
    dt = t - mark_last_t;
    if (dt >= 15000 && n_gaps < MAX_GAPS && mark_last_t)
    {
        gaps[n_gaps].from = mark_last_id;
        gaps[n_gaps].to = id;
        gaps[n_gaps].ms = dt / 1000;
        ++n_gaps;
    }
    mark_last_t = t;
    mark_last_id = id;
}

static void mark_frame(void)
{
    char buf[220];
    DWORD t, dt;
    UINT i, n = 0;

    if (!dips_on)
        return;
    t = now_us();
    dt = t - mark_frame_t;
    ++n_frames_seen;
    if (mark_frame_t && dt >= 100000)
    {
        for (i = 0; i < n_gaps && n < sizeof(buf) - 24; ++i)
            n += sprintf(buf + n, " %u>%u:%lu", gaps[i].from, gaps[i].to, gaps[i].ms);
        buf[n] = 0;
        log_line("d3d9lazy: dip t=%lu frame %u took %lu ms:%s\n", t / 1000, n_frames_seen, dt / 1000, buf);
    }
    mark_frame_t = t;
    n_gaps = 0;
}

/* Command thread. In 32-bit WineD3D every user-pointer draw and every texture lock makes the
 * calling thread wait for WineD3D's own command thread. To keep the game thread out of those
 * waits, the calls the game makes every frame (simple state setters, the batched draws,
 * BeginScene/EndScene, SetDepthStencilSurface, StretchRect, Present and the shim's overlay
 * draws) are recorded into a queue and played into Direct3D by a helper thread. Recorded calls
 * return D3D_OK at once. Every other call first waits until the queue is empty and then runs
 * on the game thread as before. With D3D9LAZY_THREAD=0 each command runs at once on the game
 * thread. */
enum { OP_RS, OP_TEX, OP_TSS, OP_SAMP, OP_FVF, OP_BEGIN, OP_END, OP_DRAW, OP_EMIT, OP_SETDS, OP_STRETCH,
        OP_PRESENT, OP_DRAWVB, OP_DEPTHREAD };
struct cmd
{
    IDirect3DDevice9 *dev;
    DWORD op, a, b, c;
    void *p;
};
struct stretch_args
{
    IDirect3DSurface9 *src, *dst;
    RECT sr, dr;
    BOOL has_sr, has_dr;
    D3DTEXTUREFILTERTYPE filter;
};
struct emit_hdr
{
    struct lazy_surf *s;
    UINT n;
    RECT rects[MAX_PEND];
};
#define Q_SIZE 8192
#define ARENA_SIZE (24u << 20)
static BOOL threading = TRUE;
static struct cmd queue[Q_SIZE];
static volatile LONG q_head, q_tail, presents_pending;
static BYTE *arena;
static SIZE_T arena_used;
static DWORD worker_tid;
static BOOL thread_ok;
static UINT present_count;
static BOOL in_exec;
static LONG n_sync, n_cmds;
static void exec_cmd(const struct cmd *c);
static volatile BOOL use_cache = TRUE;
static UINT depth_env = 1;      /* 0 = off; n = refresh the copy on every n-th lock */
static volatile UINT depth_every = 1;
static UINT depth_count;
static IDirect3DSurface9 *depth_iface, *not_depth_iface;
static BYTE *depth_buf[3];
static SIZE_T depth_size;
static INT depth_pitch;
static volatile LONG depth_published = -1, depth_held = -1;
static BOOL depth_locked;
static LONG n_depth;

/* TRUE while the shim itself is calling Direct3D to play a command. */
static BOOL on_worker(void)
{
    return threading ? GetCurrentThreadId() == worker_tid : in_exec;
}

static void wait_drained(void)
{
    while (q_tail != q_head)
        Sleep(0);
}

/* Memory for one command's data: one call per command, followed at once by push(). */
static void *arena_alloc(SIZE_T size)
{
    void *p;

    size = (size + 15) & ~(SIZE_T)15;
    if (q_tail == q_head)
        arena_used = 0;
    else if (arena_used + size > ARENA_SIZE)
    {
        wait_drained();
        arena_used = 0;
    }
    p = arena + arena_used;
    arena_used += size;
    return p;
}

static void push(IDirect3DDevice9 *dev, DWORD op, DWORD a, DWORD b, DWORD c, void *p)
{
    struct cmd tmp = {dev, op, a, b, c, p};

    ++n_cmds;
    if (!threading)
    {
        in_exec = TRUE;
        exec_cmd(&tmp);
        in_exec = FALSE;
        return;
    }
    while (q_head - q_tail >= Q_SIZE)
        Sleep(0);
    queue[q_head & (Q_SIZE - 1)] = tmp;
    InterlockedIncrement((LONG *)&q_head);
}

/* Grouped uploads. A user-pointer draw makes its caller wait until WineD3D's command thread
 * has finished everything queued, so the helper thread and WineD3D would only take turns.
 * Instead, when the helper reaches a draw it looks ahead in the queue, writes the vertices of
 * all draws queued so far (up to the end of the frame) into one vertex buffer with a single
 * lock, and turns those commands into DrawPrimitive calls on that buffer, which do not wait.
 * The triangles are written out unindexed. The buffers are used round-robin so that a buffer
 * is not locked again in the frame that draws from it (that would force a GPU flush).
 * D3D9LAZY_VB=0, or a file d3d9lazy.novb in the game directory, keeps the user-pointer draws. */
#define VB_COUNT 16
#define VB_BYTES (1u << 20)
#define GROUP_MAX 1024
static BOOL vb_allowed = TRUE;
static volatile BOOL use_vb = TRUE;
static IDirect3DVertexBuffer9 *vbs[VB_COUNT];
static UINT vb_next;
static BOOL vb_failed;
static IDirect3DVertexBuffer9 *bound_vb;
static UINT bound_stride;
static volatile BOOL stream_dirty = TRUE;
static LONG n_groups, n_vb_draws;

static void release_vbs(IDirect3DDevice9 *dev)
{
    UINT i;

    real_set_stream(dev, 0, NULL, 0, 0);
    for (i = 0; i < VB_COUNT; ++i)
    {
        if (vbs[i])
            IDirect3DVertexBuffer9_Release(vbs[i]);
        vbs[i] = NULL;
    }
    bound_vb = NULL;
    stream_dirty = TRUE;
}

static void prepare_group(LONG tail)
{
    IDirect3DDevice9 *dev = queue[tail & (Q_SIZE - 1)].dev;
    LONG head = q_head, i;
    UINT total = 0, n = 0, k, j;
    IDirect3DVertexBuffer9 *vb;
    BYTE *dst;

    for (i = tail; i != head && n < GROUP_MAX; ++i)
    {
        const struct cmd *c = &queue[i & (Q_SIZE - 1)];
        UINT start;

        if (c->op == OP_PRESENT)
            break;
        if (c->op != OP_DRAW)
            continue;
        if (c->dev != dev)
            break;
        start = (total + c->c - 1) / c->c;
        if (start * c->c + c->b * c->c > VB_BYTES)
            break;
        total = start * c->c + c->b * c->c;
        ++n;
    }
    if (!n)
        return;
    if (!(vb = vbs[vb_next]))
    {
        if (FAILED(real_create_vb(dev, VB_BYTES, D3DUSAGE_DYNAMIC | D3DUSAGE_WRITEONLY, 0, D3DPOOL_DEFAULT,
                &vbs[vb_next], NULL)))
        {
            vb_failed = TRUE;
            log_line("d3d9lazy: no vertex buffer, staying with user-pointer draws\n");
            return;
        }
        vb = vbs[vb_next];
    }
    vb_next = (vb_next + 1) % VB_COUNT;
    if (FAILED(IDirect3DVertexBuffer9_Lock(vb, 0, total, (void **)&dst, 0)))
    {
        vb_failed = TRUE;
        return;
    }
    total = 0;
    for (i = tail, k = 0; k < n; ++i)
    {
        struct cmd *c = &queue[i & (Q_SIZE - 1)];
        UINT stride = c->c, nidx = c->b, start;
        const WORD *idx = c->p;
        const BYTE *verts = (const BYTE *)c->p + ((nidx * sizeof(WORD) + 15) & ~(SIZE_T)15);
        BYTE *out;

        if (c->op != OP_DRAW)
            continue;
        start = (total + stride - 1) / stride;
        out = dst + start * stride;
        if (stride == 32)
            for (j = 0; j < nidx; ++j, out += 32)
                memcpy(out, verts + idx[j] * 32, 32);
        else
            for (j = 0; j < nidx; ++j, out += stride)
                memcpy(out, verts + idx[j] * stride, stride);
        total = start * stride + nidx * stride;
        c->a = start;
        c->b = nidx / 3;
        c->p = vb;
        c->op = OP_DRAWVB;
        ++k;
    }
    IDirect3DVertexBuffer9_Unlock(vb);
    ++n_groups;
    n_vb_draws += n;
}

static DWORD WINAPI worker_proc(void *arg)
{
    UINT idle = 0;

    for (;;)
    {
        LONG tail = q_tail;

        if (tail == q_head)
        {
            if (++idle < 2000)
                YieldProcessor();
            else if (idle < 6000)
                Sleep(0);
            else
                Sleep(1);
            continue;
        }
        idle = 0;
        if (dips_on)
        {
            DWORD t0 = now_us(), t1, t2;
            UINT op = queue[tail & (Q_SIZE - 1)].op;

            if (op == OP_DRAW && use_vb && !vb_failed)
                prepare_group(tail);
            t1 = now_us();
            exec_cmd(&queue[tail & (Q_SIZE - 1)]);
            t2 = now_us();
            if (t2 - t0 >= 40000)
                log_line("d3d9lazy: helper t=%lu op %u took %lu ms (group upload %lu ms)\n", t2 / 1000, op,
                        (t2 - t0) / 1000, (t1 - t0) / 1000);
            InterlockedIncrement((LONG *)&q_tail);
            continue;
        }
        if (queue[tail & (Q_SIZE - 1)].op == OP_DRAW && use_vb && !vb_failed)
            prepare_group(tail);
        exec_cmd(&queue[tail & (Q_SIZE - 1)]);
        InterlockedIncrement((LONG *)&q_tail);
    }
    return 0;
}

/* Record the collected triangles as one draw. */
static void close_batch(void)
{
    UINT nverts = batch_nverts, nidx = batch_nidx;
    SIZE_T ibytes = (nidx * sizeof(WORD) + 15) & ~(SIZE_T)15;
    BYTE *p;

    if (!nidx)
        return;
    batch_nverts = batch_nidx = 0;
    ++n_draws_out;
    p = arena_alloc(ibytes + nverts * batch_stride);
    memcpy(p, batch_idx, nidx * sizeof(WORD));
    memcpy(p + ibytes, batch_verts, nverts * batch_stride);
    push(batch_dev, OP_DRAW, nverts, nidx, batch_stride, p);
}

/* Thunk callback: everything recorded must have reached Direct3D before the call that follows. */
static void __cdecl flush_batch(void)
{
    if (on_worker())
        return;
    close_batch();
    if (q_tail != q_head)
    {
        ++n_sync;
        wait_drained();
    }
}

static IDirect3DSurface9 *bb_cache;
static IDirect3DDevice9 *bb_dev;

static HRESULT WINAPI hook_reset(IDirect3DDevice9 *dev, D3DPRESENT_PARAMETERS *pp)
{
    int i;

    emit_all();
    release_vbs(dev);
    depth_iface = not_depth_iface = NULL;
    depth_published = depth_held = -1;
    depth_locked = FALSE;
    shadow_forget();
    bb_cache = NULL;
    for (i = 0; i < MAX_SURF; ++i)
    {
        if (surfs[i].buf) VirtualFree(surfs[i].buf, 0, MEM_RELEASE);
        if (surfs[i].pbuf) VirtualFree(surfs[i].pbuf, 0, MEM_RELEASE);
        memset(&surfs[i], 0, sizeof(surfs[i]));
    }
    return real_reset(dev, pp);
}

/* Make room for a draw; FALSE means it cannot be batched. */
static BOOL batch_reserve(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE type, UINT count, UINT nv, UINT stride)
{
    if (!batching || !count || !nv || stride > BATCH_MAX_STRIDE || nv > BATCH_MAX_VERTS
            || count * 3 > BATCH_MAX_IDX
            || (type != D3DPT_TRIANGLELIST && type != D3DPT_TRIANGLESTRIP && type != D3DPT_TRIANGLEFAN))
        return FALSE;
    if (batch_nidx && (dev != batch_dev || stride != batch_stride
            || batch_nverts + nv > BATCH_MAX_VERTS || batch_nidx + count * 3 > BATCH_MAX_IDX))
        close_batch();
    batch_dev = dev;
    batch_stride = stride;
    return TRUE;
}

static HRESULT WINAPI hook_dpup(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE type, UINT count,
        const void *data, UINT stride)
{
    UINT nv = type == D3DPT_TRIANGLELIST ? count * 3 : count + 2, base, i;
    WORD *ix;

    mark(200);
    check_draw_against_pending(dev, data, nv, stride);
    if (!data || !batch_reserve(dev, type, count, nv, stride))
    {
        flush_batch();
        ++n_draws_pass;
        stream_dirty = TRUE;
        return real_dpup(dev, type, count, data, stride);
    }
    ++n_draws_in;
    base = batch_nverts;
    memcpy(batch_verts + base * stride, data, nv * stride);
    batch_nverts += nv;
    ix = batch_idx + batch_nidx;
    batch_nidx += count * 3;
    if (type == D3DPT_TRIANGLELIST)
        for (i = 0; i < nv; ++i)
            ix[i] = base + i;
    else if (type == D3DPT_TRIANGLEFAN)
        for (i = 0; i < count; ++i, ix += 3)
        {
            ix[0] = base; ix[1] = base + i + 1; ix[2] = base + i + 2;
        }
    else
        for (i = 0; i < count; ++i, ix += 3)
        {
            ix[0] = base + i + (i & 1); ix[1] = base + i + 1 - (i & 1); ix[2] = base + i + 2;
        }
    return D3D_OK;
}

static HRESULT WINAPI hook_dipup(IDirect3DDevice9 *dev, D3DPRIMITIVETYPE type, UINT min_idx, UINT nv,
        UINT count, const void *idx_data, D3DFORMAT idx_fmt, const void *data, UINT stride)
{
    UINT ni = type == D3DPT_TRIANGLELIST ? count * 3 : count + 2, base, i;
    const WORD *s16 = idx_data;
    const DWORD *s32 = idx_data;
    BOOL wide = idx_fmt == D3DFMT_INDEX32;
    BOOL ok = data && idx_data && (idx_fmt == D3DFMT_INDEX16 || idx_fmt == D3DFMT_INDEX32);
    WORD *ix;

    mark(201);
    check_draw_against_pending(dev, data ? (const BYTE *)data + min_idx * stride : NULL, nv, stride);
    /* All indices must lie in [min_idx, min_idx + nv). */
    for (i = 0; ok && i < ni && ni <= BATCH_MAX_IDX; ++i)
        if ((wide ? s32[i] : s16[i]) - min_idx >= nv)
            ok = FALSE;
    if (!ok || !batch_reserve(dev, type, count, nv, stride))
    {
        flush_batch();
        ++n_draws_pass;
        stream_dirty = TRUE;
        return real_dipup(dev, type, min_idx, nv, count, idx_data, idx_fmt, data, stride);
    }
    ++n_draws_in;
    base = batch_nverts;
    memcpy(batch_verts + base * stride, (const BYTE *)data + min_idx * stride, nv * stride);
    batch_nverts += nv;
    ix = batch_idx + batch_nidx;
    batch_nidx += count * 3;
#define IDX(n) ((WORD)(base + (wide ? s32[n] : s16[n]) - min_idx))
    if (type == D3DPT_TRIANGLELIST)
        for (i = 0; i < ni; ++i)
            ix[i] = IDX(i);
    else if (type == D3DPT_TRIANGLEFAN)
        for (i = 0; i < count; ++i, ix += 3)
        {
            ix[0] = IDX(0); ix[1] = IDX(i + 1); ix[2] = IDX(i + 2);
        }
    else
        for (i = 0; i < count; ++i, ix += 3)
        {
            ix[0] = IDX(i + (i & 1)); ix[1] = IDX(i + 1 - (i & 1)); ix[2] = IDX(i + 2);
        }
#undef IDX
    return D3D_OK;
}

/* Redundant state calls. The game sets many states to the value they already have, and each
 * such call would end the current batch. The shim keeps a shadow copy of the simple states;
 * a call that changes nothing returns at once without touching the batch. The shim's own
 * state changes go through the same hooks, so the shadow stays right. State blocks change
 * device state behind the shim's back: the first use of one switches the filter off. */
#define SH_RS 256
#define SH_STAGES 8
#define SH_TSS 33
#define SH_SAMPLERS 16
#define SH_SAMP 14
static BOOL filtering = TRUE;
static IDirect3DDevice9 *sh_dev;
static DWORD sh_rs[SH_RS], sh_tss[SH_STAGES][SH_TSS], sh_samp[SH_SAMPLERS][SH_SAMP], sh_fvf;
static BYTE sh_rs_ok[SH_RS], sh_tss_ok[SH_STAGES][SH_TSS], sh_samp_ok[SH_SAMPLERS][SH_SAMP], sh_fvf_ok;
static IDirect3DBaseTexture9 *sh_tex[SH_STAGES];
static BYTE sh_tex_ok[SH_STAGES];
static LONG n_state, n_state_skip;
static HRESULT (WINAPI *real_set_rs)(IDirect3DDevice9 *, D3DRENDERSTATETYPE, DWORD);
static HRESULT (WINAPI *real_set_tex)(IDirect3DDevice9 *, DWORD, IDirect3DBaseTexture9 *);
static HRESULT (WINAPI *real_set_tss)(IDirect3DDevice9 *, DWORD, D3DTEXTURESTAGESTATETYPE, DWORD);
static HRESULT (WINAPI *real_set_samp)(IDirect3DDevice9 *, DWORD, D3DSAMPLERSTATETYPE, DWORD);
static HRESULT (WINAPI *real_set_fvf)(IDirect3DDevice9 *, DWORD);

static void shadow_forget(void)
{
    memset(sh_rs_ok, 0, sizeof(sh_rs_ok));
    memset(sh_tss_ok, 0, sizeof(sh_tss_ok));
    memset(sh_samp_ok, 0, sizeof(sh_samp_ok));
    memset(sh_tex_ok, 0, sizeof(sh_tex_ok));
    sh_fvf_ok = 0;
}

/* Thunk callbacks for calls that invalidate part of the shadow. */
static void __cdecl flush_stream_dirty(void)
{
    if (on_worker())
        return;
    flush_batch();
    stream_dirty = TRUE;
}

static void __cdecl flush_forget_fvf(void)
{
    if (on_worker())
        return;
    flush_batch();
    sh_fvf_ok = 0;
}

static void __cdecl flush_filter_off(void)
{
    if (on_worker())
        return;
    flush_batch();
    if (filtering)
        log_line("d3d9lazy: state block used, redundant-state filter off\n");
    filtering = FALSE;
    shadow_forget();
}

static BOOL shadow_dev(IDirect3DDevice9 *dev)
{
    if (!filtering)
        return FALSE;
    if (dev != sh_dev)
    {
        shadow_forget();
        sh_dev = dev;
    }
    return TRUE;
}

static HRESULT WINAPI hook_set_rs(IDirect3DDevice9 *dev, D3DRENDERSTATETYPE state, DWORD value)
{
    BOOL track;

    if (on_worker())
        return real_set_rs(dev, state, value);
    mark(202);
    track = shadow_dev(dev) && (UINT)state < SH_RS;
    ++n_state;
    if (track && sh_rs_ok[state] && sh_rs[state] == value)
    {
        ++n_state_skip;
        return D3D_OK;
    }
    close_batch();
    push(dev, OP_RS, state, value, 0, NULL);
    if (track)
    {
        sh_rs[state] = value;
        sh_rs_ok[state] = 1;
    }
    return D3D_OK;
}

static HRESULT WINAPI hook_set_tex(IDirect3DDevice9 *dev, DWORD stage, IDirect3DBaseTexture9 *tex)
{
    BOOL track;

    if (on_worker())
        return real_set_tex(dev, stage, tex);
    mark(203);
    track = shadow_dev(dev) && stage < SH_STAGES;
    ++n_state;
    if (track && sh_tex_ok[stage] && sh_tex[stage] == tex)
    {
        ++n_state_skip;
        return D3D_OK;
    }
    close_batch();
    /* Keep the texture alive until the command has run. */
    if (tex)
        IDirect3DBaseTexture9_AddRef(tex);
    push(dev, OP_TEX, stage, 0, 0, tex);
    if (track)
    {
        sh_tex[stage] = tex;
        sh_tex_ok[stage] = 1;
    }
    return D3D_OK;
}

static HRESULT WINAPI hook_set_tss(IDirect3DDevice9 *dev, DWORD stage, D3DTEXTURESTAGESTATETYPE type, DWORD value)
{
    BOOL track;

    if (on_worker())
        return real_set_tss(dev, stage, type, value);
    mark(204);
    track = shadow_dev(dev) && stage < SH_STAGES && (UINT)type < SH_TSS;
    ++n_state;
    if (track && sh_tss_ok[stage][type] && sh_tss[stage][type] == value)
    {
        ++n_state_skip;
        return D3D_OK;
    }
    close_batch();
    push(dev, OP_TSS, stage, type, value, NULL);
    if (track)
    {
        sh_tss[stage][type] = value;
        sh_tss_ok[stage][type] = 1;
    }
    return D3D_OK;
}

static HRESULT WINAPI hook_get_tss(IDirect3DDevice9 *dev, DWORD stage, D3DTEXTURESTAGESTATETYPE type, DWORD *value)
{
    BOOL track;
    HRESULT hr;

    if (on_worker())
        return real_get_tss(dev, stage, type, value);
    mark(213);
    track = value && shadow_dev(dev) && stage < SH_STAGES && (UINT)type < SH_TSS;
    if (track && sh_tss_ok[stage][type])
    {
        *value = sh_tss[stage][type];
        return D3D_OK;
    }
    flush_batch();
    hr = real_get_tss(dev, stage, type, value);
    if (track && SUCCEEDED(hr))
    {
        sh_tss[stage][type] = *value;
        sh_tss_ok[stage][type] = 1;
    }
    return hr;
}

static HRESULT WINAPI hook_set_samp(IDirect3DDevice9 *dev, DWORD sampler, D3DSAMPLERSTATETYPE type, DWORD value)
{
    BOOL track;

    if (on_worker())
        return real_set_samp(dev, sampler, type, value);
    mark(205);
    track = shadow_dev(dev) && sampler < SH_SAMPLERS && (UINT)type < SH_SAMP;
    ++n_state;
    if (track && sh_samp_ok[sampler][type] && sh_samp[sampler][type] == value)
    {
        ++n_state_skip;
        return D3D_OK;
    }
    close_batch();
    push(dev, OP_SAMP, sampler, type, value, NULL);
    if (track)
    {
        sh_samp[sampler][type] = value;
        sh_samp_ok[sampler][type] = 1;
    }
    return D3D_OK;
}

static HRESULT WINAPI hook_set_fvf(IDirect3DDevice9 *dev, DWORD fvf)
{
    BOOL track;

    if (on_worker())
        return real_set_fvf(dev, fvf);
    mark(206);
    track = shadow_dev(dev);
    ++n_state;
    if (track && sh_fvf_ok && sh_fvf == fvf)
    {
        ++n_state_skip;
        return D3D_OK;
    }
    close_batch();
    push(dev, OP_FVF, fvf, 0, 0, NULL);
    if (track)
    {
        sh_fvf = fvf;
        sh_fvf_ok = 1;
    }
    return D3D_OK;
}

static HRESULT WINAPI hook_begin(IDirect3DDevice9 *dev)
{
    if (on_worker())
        return real_begin(dev);
    mark(207);
    close_batch();
    push(dev, OP_BEGIN, 0, 0, 0, NULL);
    return D3D_OK;
}

static HRESULT WINAPI hook_end(IDirect3DDevice9 *dev)
{
    if (on_worker())
        return real_end(dev);
    mark(208);
    close_batch();
    push(dev, OP_END, 0, 0, 0, NULL);
    return D3D_OK;
}

static HRESULT WINAPI hook_set_ds(IDirect3DDevice9 *dev, IDirect3DSurface9 *surface)
{
    if (on_worker())
        return real_set_ds(dev, surface);
    mark(209);
    emit_record();
    close_batch();
    if (surface)
        IDirect3DSurface9_AddRef(surface);
    push(dev, OP_SETDS, 0, 0, 0, surface);
    return D3D_OK;
}

static HRESULT WINAPI hook_stretch(IDirect3DDevice9 *dev, IDirect3DSurface9 *src, const RECT *sr,
        IDirect3DSurface9 *dst, const RECT *dr, D3DTEXTUREFILTERTYPE filter)
{
    struct stretch_args *st;

    if (on_worker())
        return real_stretch(dev, src, sr, dst, dr, filter);
    mark(210);
    if (!src || !dst)
    {
        emit_all();
        return real_stretch(dev, src, sr, dst, dr, filter);
    }
    emit_record();
    close_batch();
    st = arena_alloc(sizeof(*st));
    st->src = src;
    st->dst = dst;
    st->has_sr = !!sr;
    st->has_dr = !!dr;
    if (sr) st->sr = *sr;
    if (dr) st->dr = *dr;
    st->filter = filter;
    IDirect3DSurface9_AddRef(src);
    IDirect3DSurface9_AddRef(dst);
    push(dev, OP_STRETCH, 0, 0, 0, st);
    return D3D_OK;
}

/* The game may run at most one frame ahead of the helper thread. */
static HRESULT WINAPI hook_present(IDirect3DDevice9 *dev, const RECT *sr, const RECT *dr, HWND wnd,
        const RGNDATA *dirty)
{
    if (on_worker())
        return real_present(dev, sr, dr, wnd, dirty);
    mark(211);
    if (sr || dr || wnd || dirty)
    {
        emit_all();
        return real_present(dev, sr, dr, wnd, dirty);
    }
    emit_record();
    close_batch();
    /* Live switch for A/B measurements: while a file named d3d9lazy.nothread exists in the
     * game directory, commands run at once on the game thread. */
    if (thread_ok && !(++present_count & 31))
    {
        BOOL want = GetFileAttributesA("d3d9lazy.nothread") == INVALID_FILE_ATTRIBUTES;

        use_vb = vb_allowed && GetFileAttributesA("d3d9lazy.novb") == INVALID_FILE_ATTRIBUTES;
        dips_on = logging && GetFileAttributesA("d3d9lazy.dips") != INVALID_FILE_ATTRIBUTES;
        depth_every = GetFileAttributesA("d3d9lazy.nodepth") != INVALID_FILE_ATTRIBUTES ? 0
                : GetFileAttributesA("d3d9lazy.depth2") != INVALID_FILE_ATTRIBUTES ? 2 : depth_env;
        use_cache = GetFileAttributesA("d3d9lazy.nocache") == INVALID_FILE_ATTRIBUTES;
        if (want != threading)
        {
            wait_drained();
            threading = want;
            log_line("d3d9lazy: command thread switched %s\n", want ? "on" : "off");
        }
    }
    while (presents_pending >= 1)
        Sleep(0);
    mark(1211);
    mark_frame();
    InterlockedIncrement((LONG *)&presents_pending);
    push(dev, OP_PRESENT, 0, 0, 0, NULL);
    return D3D_OK;
}

/* The implicit back buffer lives until Reset, so its address can be handed out without
 * asking Direct3D (the game asks once per frame). */
static HRESULT WINAPI hook_get_bb(IDirect3DDevice9 *dev, UINT swapchain, UINT idx, D3DBACKBUFFER_TYPE type,
        IDirect3DSurface9 **out)
{
    HRESULT hr;

    if (on_worker())
        return real_get_bb(dev, swapchain, idx, type, out);
    mark(212);
    if (!swapchain && !idx && type == D3DBACKBUFFER_TYPE_MONO && out && bb_cache && bb_dev == dev)
    {
        IDirect3DSurface9_AddRef(bb_cache);
        *out = bb_cache;
        return D3D_OK;
    }
    flush_batch();
    hr = real_get_bb(dev, swapchain, idx, type, out);
    if (SUCCEEDED(hr) && !swapchain && !idx && type == D3DBACKBUFFER_TYPE_MONO && out)
    {
        bb_cache = *out;
        bb_dev = dev;
    }
    return hr;
}

/* Thunk callbacks: each gets the id of the call it precedes. */
static void __cdecl th_flush(UINT id)
{
    if (on_worker())
        return;
    mark(id);
    flush_batch();
    mark(1000 + id);
}

static void __cdecl th_emit(UINT id)
{
    if (on_worker())
        return;
    mark(id);
    emit_all();
    mark(1000 + id);
}

static void __cdecl th_stream(UINT id)
{
    mark(id);
    flush_stream_dirty();
    mark(1000 + id);
}

static void __cdecl th_fvf(UINT id)
{
    mark(id);
    flush_forget_fvf();
    mark(1000 + id);
}

static void __cdecl th_off(UINT id)
{
    mark(id);
    flush_filter_off();
    mark(1000 + id);
}

/* A generated stub: save registers, call fn(id), restore, jump to the original. */
static void *make_thunk(void *target, void (__cdecl *fn)(UINT), UINT id)
{
    static BYTE *page, *next;
    BYTE *t;

    if (!page)
    {
        if (!(page = VirtualAlloc(NULL, 4096, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE)))
            return target;
        next = page;
    }
    if (next + 24 > page + 4096)
        return target;
    t = next;
    next += 24;
    t[0] = 0x60;                                    /* pushad */
    t[1] = 0x9c;                                    /* pushfd */
    t[2] = 0x68;                                    /* push id */
    *(DWORD *)(t + 3) = id;
    t[7] = 0xe8;                                    /* call fn */
    *(DWORD *)(t + 8) = (DWORD)((BYTE *)fn - (t + 12));
    t[12] = 0x83; t[13] = 0xc4; t[14] = 0x04;       /* add esp, 4 */
    t[15] = 0x9d;                                   /* popfd */
    t[16] = 0x61;                                   /* popad */
    t[17] = 0xe9;                                   /* jmp target */
    *(DWORD *)(t + 18) = (DWORD)((BYTE *)target - (t + 22));
    return t;
}

static void fill_key(struct lazy_surf *s, const RECT *r)
{
    UINT y, x;

    for (y = r->top; y < r->bottom; ++y)
    {
        WORD *row = (WORD *)(s->buf + y * s->pitch);
        for (x = r->left; x < r->right; ++x)
            row[x] = KEY16;
    }
}

/* Bounding rectangle of all pixels that are not the key colour. */
static BOOL find_changes(struct lazy_surf *s, RECT *r, UINT *count)
{
    UINT y, x, w2 = s->width / 2, n = 0;
    LONG left = s->width, right = 0, top = -1, bottom = 0;

    for (y = 0; y < s->height; ++y)
    {
        const DWORD *row = (const DWORD *)(s->buf + y * s->pitch);
        BOOL hit = FALSE;

        if (!memcmp(row, key_row, s->width * 2))
            continue;
        for (x = 0; x < w2; ++x)
        {
            if (row[x] == KEY32)
                continue;
            hit = TRUE;
            ++n;
            if ((LONG)(x * 2) < left) left = x * 2;
            if ((LONG)(x * 2 + 2) > right) right = x * 2 + 2;
        }
        if (hit)
        {
            if (top < 0) top = y;
            bottom = y + 1;
        }
    }
    *count = n * 2;
    if (top < 0)
        return FALSE;
    SetRect(r, left, top, right, bottom);
    return TRUE;
}

struct quad_vertex
{
    float x, y, z, rhw;
    float u, v;
};

static const D3DRENDERSTATETYPE rs_list[] =
{
    D3DRS_ZENABLE, D3DRS_ZWRITEENABLE, D3DRS_CULLMODE, D3DRS_LIGHTING, D3DRS_FOGENABLE,
    D3DRS_ALPHABLENDENABLE, D3DRS_SRCBLEND, D3DRS_DESTBLEND, D3DRS_BLENDOP,
    D3DRS_SEPARATEALPHABLENDENABLE, D3DRS_ALPHATESTENABLE, D3DRS_ALPHAREF, D3DRS_ALPHAFUNC,
    D3DRS_STENCILENABLE, D3DRS_SCISSORTESTENABLE, D3DRS_CLIPPLANEENABLE, D3DRS_FILLMODE,
    D3DRS_COLORWRITEENABLE, D3DRS_SRGBWRITEENABLE, D3DRS_SHADEMODE, D3DRS_SPECULARENABLE,
};
static const DWORD rs_value[] =
{
    D3DZB_FALSE, FALSE, D3DCULL_NONE, FALSE, FALSE,
    TRUE, D3DBLEND_SRCALPHA, D3DBLEND_INVSRCALPHA, D3DBLENDOP_ADD,
    FALSE, TRUE, 0x80, D3DCMP_GREATEREQUAL,
    FALSE, FALSE, 0, D3DFILL_SOLID,
    0xf, FALSE, D3DSHADE_GOURAUD, FALSE,
};
static const D3DTEXTURESTAGESTATETYPE tss_list[] =
{
    D3DTSS_COLOROP, D3DTSS_COLORARG1, D3DTSS_ALPHAOP, D3DTSS_ALPHAARG1,
    D3DTSS_TEXCOORDINDEX, D3DTSS_TEXTURETRANSFORMFLAGS,
};
static const DWORD tss_value[] =
{
    D3DTOP_SELECTARG1, D3DTA_TEXTURE, D3DTOP_SELECTARG1, D3DTA_TEXTURE, 0, D3DTTFF_DISABLE,
};
static const D3DSAMPLERSTATETYPE samp_list[] =
{
    D3DSAMP_MINFILTER, D3DSAMP_MAGFILTER, D3DSAMP_MIPFILTER, D3DSAMP_ADDRESSU, D3DSAMP_ADDRESSV,
    D3DSAMP_SRGBTEXTURE,
};
static const DWORD samp_value[] =
{
    D3DTEXF_POINT, D3DTEXF_POINT, D3DTEXF_NONE, D3DTADDRESS_CLAMP, D3DTADDRESS_CLAMP, FALSE,
};
#define COUNT(a) (sizeof(a) / sizeof((a)[0]))

/* Overlay cache. Most bands (toolbar, unit cards) hold the same pixels frame after frame.
 * The helper thread keeps the last pixels of each band position with the texture they were
 * uploaded to; a band that has not changed is drawn from that texture again with no lock and
 * no upload. A texture that a recently used cache entry owns is skipped by the round-robin.
 * A file d3d9lazy.nocache in the game directory switches the cache off. */
#define CACHE_N 12
#define CACHE_FRESH 16
struct overlay_cache
{
    RECT r;
    IDirect3DTexture9 *tex;
    UINT tw, th;
    BYTE *pix;
    SIZE_T cap, bytes;
    DWORD stamp;
};
static struct overlay_cache ocache[CACHE_N];
static DWORD ocache_clock;
static LONG n_cache_hit, n_cache_miss;

/* Upload one rectangle (w*h R5G6B5 pixels, rows packed) to a pool texture. */
static IDirect3DTexture9 *upload_rect(const BYTE *pix, const RECT *r, UINT *tw, UINT *th)
{
    UINT y, x, w = r->right - r->left, h = r->bottom - r->top, c, i, k;
    SIZE_T bytes = (SIZE_T)w * h * sizeof(WORD);
    struct overlay_cache *e = NULL, *lru = &ocache[0];
    IDirect3DTexture9 *tex = NULL;
    D3DLOCKED_RECT lr;
    RECT tr;

    ++ocache_clock;
    if (use_cache)
    {
        for (i = 0; i < CACHE_N; ++i)
        {
            if (ocache[i].tex && EqualRect(&ocache[i].r, r))
                e = &ocache[i];
            if (ocache[i].stamp < lru->stamp)
                lru = &ocache[i];
        }
        if (e && e->bytes == bytes && !memcmp(e->pix, pix, bytes))
        {
            e->stamp = ocache_clock;
            *tw = e->tw;
            *th = e->th;
            ++n_cache_hit;
            return e->tex;
        }
        ++n_cache_miss;
        if (!e)
            e = lru;
    }
    for (c = 0; c < POOL_CLASSES - 1 && (w > pool_w[c] || h > pool_h[c]); ++c) ;
    *tw = pool_w[c];
    *th = pool_h[c];
    /* Next texture of the class that no fresh cache entry owns (the last one tried otherwise). */
    for (k = 0; k < pool_count[c]; ++k)
    {
        BOOL owned = FALSE;

        tex = pool[c][pool_next[c]];
        pool_next[c] = (pool_next[c] + 1) % pool_count[c];
        for (i = 0; i < CACHE_N; ++i)
            if (ocache[i].tex == tex && ocache_clock - ocache[i].stamp <= CACHE_FRESH)
                owned = TRUE;
        if (!owned)
            break;
    }
    for (i = 0; i < CACHE_N; ++i)
        if (ocache[i].tex == tex)
            ocache[i].tex = NULL;
    if (e)
    {
        if (e->cap < bytes)
        {
            if (e->pix)
                HeapFree(GetProcessHeap(), 0, e->pix);
            e->pix = HeapAlloc(GetProcessHeap(), 0, bytes);
            e->cap = e->pix ? bytes : 0;
        }
        e->tex = NULL;
        if (e->pix)
        {
            memcpy(e->pix, pix, bytes);
            e->bytes = bytes;
            e->r = *r;
            e->tw = *tw;
            e->th = *th;
            e->stamp = ocache_clock;
            e->tex = tex;
        }
    }
    SetRect(&tr, 0, 0, w, h);
    if (FAILED(IDirect3DTexture9_LockRect(tex, 0, &lr, &tr, 0)))
    {
        if (e)
            e->tex = NULL;
        return NULL;
    }
    for (y = 0; y < h; ++y)
    {
        const WORD *src = (const WORD *)pix + y * w;
        DWORD *dst = (DWORD *)((BYTE *)lr.pBits + y * lr.Pitch);

        for (x = 0; x < w; ++x)
        {
            DWORD p = src[x];
            /* R5G6B5 -> A8R8G8B8, alpha 0 for the key colour. */
            dst[x] = p == KEY16 ? 0 : (0xff000000u | ((p & 0xf800) << 8) | ((p & 0xe000) << 3)
                    | ((p & 0x07e0) << 5) | ((p & 0x0600) >> 1) | ((p & 0x001f) << 3) | ((p & 0x001c) >> 2));
        }
    }
    IDirect3DTexture9_UnlockRect(tex, 0);
    return tex;
}

/* Draw rectangles of the pending buffer over the render target with the key colour
 * transparent. Only the states listed above are touched; each is read first and put back
 * after. The depth buffer binding is left alone, because changing it would split the GPU
 * job. */
static BOOL draw_overlays(struct lazy_surf *s, const RECT *rects, UINT n, const BYTE *pix)
{
    IDirect3DDevice9 *dev = s->device;
    IDirect3DSurface9 *old_rt = NULL;
    IDirect3DBaseTexture9 *old_tex0 = NULL, *old_tex1 = NULL;
    IDirect3DVertexShader9 *old_vs = NULL;
    IDirect3DPixelShader9 *old_ps = NULL;
    IDirect3DVertexDeclaration9 *old_decl = NULL;
    DWORD old_rs[COUNT(rs_list)], old_tss[COUNT(tss_list)], old_samp[COUNT(samp_list)];
    DWORD old_fvf = 0, old_colorop1 = 0, old_alphaop1 = 0;
    IDirect3DTexture9 *tex[MAX_PEND];
    UINT tw[MAX_PEND], th[MAX_PEND], i, k;
    D3DVIEWPORT9 old_vp, vp;
    struct quad_vertex q[4];
    BOOL ok = TRUE, began;

    for (k = 0; k < n; ++k)
    {
        if (!(tex[k] = upload_rect(pix, &rects[k], &tw[k], &th[k])))
            ok = FALSE;
        pix += (rects[k].right - rects[k].left) * (rects[k].bottom - rects[k].top) * sizeof(WORD);
    }

    /* Save. */
    IDirect3DDevice9_GetRenderTarget(dev, 0, &old_rt);
    IDirect3DDevice9_GetViewport(dev, &old_vp);
    IDirect3DDevice9_GetTexture(dev, 0, &old_tex0);
    IDirect3DDevice9_GetTexture(dev, 1, &old_tex1);
    IDirect3DDevice9_GetVertexShader(dev, &old_vs);
    IDirect3DDevice9_GetPixelShader(dev, &old_ps);
    IDirect3DDevice9_GetVertexDeclaration(dev, &old_decl);
    IDirect3DDevice9_GetFVF(dev, &old_fvf);
    for (i = 0; i < COUNT(rs_list); ++i)
        IDirect3DDevice9_GetRenderState(dev, rs_list[i], &old_rs[i]);
    for (i = 0; i < COUNT(tss_list); ++i)
        IDirect3DDevice9_GetTextureStageState(dev, 0, tss_list[i], &old_tss[i]);
    IDirect3DDevice9_GetTextureStageState(dev, 1, D3DTSS_COLOROP, &old_colorop1);
    IDirect3DDevice9_GetTextureStageState(dev, 1, D3DTSS_ALPHAOP, &old_alphaop1);
    for (i = 0; i < COUNT(samp_list); ++i)
        IDirect3DDevice9_GetSamplerState(dev, 0, samp_list[i], &old_samp[i]);

    /* Set. */
    if (old_rt != s->iface)
        IDirect3DDevice9_SetRenderTarget(dev, 0, s->iface);
    vp.X = vp.Y = 0; vp.Width = s->width; vp.Height = s->height; vp.MinZ = 0.0f; vp.MaxZ = 1.0f;
    IDirect3DDevice9_SetViewport(dev, &vp);
    IDirect3DDevice9_SetVertexShader(dev, NULL);
    IDirect3DDevice9_SetPixelShader(dev, NULL);
    IDirect3DDevice9_SetFVF(dev, D3DFVF_XYZRHW | D3DFVF_TEX1);
    IDirect3DDevice9_SetTexture(dev, 1, NULL);
    for (i = 0; i < COUNT(rs_list); ++i)
        if (old_rs[i] != rs_value[i])
            IDirect3DDevice9_SetRenderState(dev, rs_list[i], rs_value[i]);
    for (i = 0; i < COUNT(tss_list); ++i)
        if (old_tss[i] != tss_value[i])
            IDirect3DDevice9_SetTextureStageState(dev, 0, tss_list[i], tss_value[i]);
    IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_COLOROP, D3DTOP_DISABLE);
    IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
    for (i = 0; i < COUNT(samp_list); ++i)
        if (old_samp[i] != samp_value[i])
            IDirect3DDevice9_SetSamplerState(dev, 0, samp_list[i], samp_value[i]);

    /* An early emit can happen inside one of the game's scenes; BeginScene then fails
     * and the scene must be left open. */
    began = SUCCEEDED(IDirect3DDevice9_BeginScene(dev));
    {
        for (k = 0; k < n; ++k)
        {
            const RECT *r = &rects[k];

            if (!tex[k])
                continue;
#define V(i, px, py) q[i].x = (px) - 0.5f; q[i].y = (py) - 0.5f; q[i].z = 0.0f; q[i].rhw = 1.0f; \
        q[i].u = (float)((px) - r->left) / tw[k]; q[i].v = (float)((py) - r->top) / th[k]
            V(0, r->left, r->top);
            V(1, r->right, r->top);
            V(2, r->left, r->bottom);
            V(3, r->right, r->bottom);
#undef V
            IDirect3DDevice9_SetTexture(dev, 0, (IDirect3DBaseTexture9 *)tex[k]);
            if (FAILED((real_dpup ? real_dpup : dev->lpVtbl->DrawPrimitiveUP)(dev, D3DPT_TRIANGLESTRIP, 2,
                    q, sizeof(*q))))
                ok = FALSE;
        }
        if (began)
            IDirect3DDevice9_EndScene(dev);
    }

    /* Restore. */
    for (i = 0; i < COUNT(samp_list); ++i)
        if (old_samp[i] != samp_value[i])
            IDirect3DDevice9_SetSamplerState(dev, 0, samp_list[i], old_samp[i]);
    IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_ALPHAOP, old_alphaop1);
    IDirect3DDevice9_SetTextureStageState(dev, 1, D3DTSS_COLOROP, old_colorop1);
    for (i = 0; i < COUNT(tss_list); ++i)
        if (old_tss[i] != tss_value[i])
            IDirect3DDevice9_SetTextureStageState(dev, 0, tss_list[i], old_tss[i]);
    for (i = 0; i < COUNT(rs_list); ++i)
        if (old_rs[i] != rs_value[i])
            IDirect3DDevice9_SetRenderState(dev, rs_list[i], old_rs[i]);
    IDirect3DDevice9_SetTexture(dev, 1, old_tex1);
    IDirect3DDevice9_SetTexture(dev, 0, old_tex0);
    if (old_decl)
        IDirect3DDevice9_SetVertexDeclaration(dev, old_decl);
    else
        IDirect3DDevice9_SetFVF(dev, old_fvf);
    IDirect3DDevice9_SetPixelShader(dev, old_ps);
    IDirect3DDevice9_SetVertexShader(dev, old_vs);
    IDirect3DDevice9_SetViewport(dev, &old_vp);
    if (old_rt && old_rt != s->iface)
        IDirect3DDevice9_SetRenderTarget(dev, 0, old_rt);

    if (old_rt) IDirect3DSurface9_Release(old_rt);
    if (old_tex0) IDirect3DBaseTexture9_Release(old_tex0);
    if (old_tex1) IDirect3DBaseTexture9_Release(old_tex1);
    if (old_vs) IDirect3DVertexShader9_Release(old_vs);
    if (old_ps) IDirect3DPixelShader9_Release(old_ps);
    if (old_decl) IDirect3DVertexDeclaration9_Release(old_decl);
    return ok;
}

static void fill_key_buf(struct lazy_surf *s, BYTE *buf, const RECT *r)
{
    UINT y, x;

    for (y = r->top; y < r->bottom; ++y)
    {
        WORD *row = (WORD *)(buf + y * s->pitch);
        for (x = r->left; x < r->right; ++x)
            row[x] = KEY16;
    }
}

/* Record everything pending for one surface: merge vertically overlapping rectangles into
 * bands, one texture and quad per band. The pixels are copied into the command. */
static void emit_pending(struct lazy_surf *s)
{
    RECT bands[MAX_PEND];
    UINT nb = 0, i, k;
    SIZE_T bytes = 0;
    struct emit_hdr *hdr;
    BYTE *dst;
    LONG y;

    if (!s->n_pend)
        return;
    close_batch();
    for (i = 0; i < s->n_pend; ++i)
    {
        const RECT *r = &s->pend[i];

        for (k = 0; k < nb; ++k)
            if (r->top < bands[k].bottom && r->bottom > bands[k].top)
                break;
        if (k == nb)
            bands[nb++] = *r;
        else
            UnionRect(&bands[k], &bands[k], r);
    }
    s->n_pend = 0;
    ++n_emits;
    n_bands += nb;
    if (dips_on && n_band_log < 60)
        for (k = 0; k < nb; ++k, ++n_band_log)
            log_line("d3d9lazy: band %ldx%ld at (%ld,%ld) frame %u\n", bands[k].right - bands[k].left,
                    bands[k].bottom - bands[k].top, bands[k].left, bands[k].top, n_frames_seen);
    if (mode == MODE_OVERLAY)
    {
        for (k = 0; k < nb; ++k)
            bytes += (bands[k].right - bands[k].left) * (bands[k].bottom - bands[k].top) * sizeof(WORD);
        hdr = arena_alloc(sizeof(*hdr) + bytes);
        hdr->s = s;
        hdr->n = nb;
        dst = (BYTE *)(hdr + 1);
        for (k = 0; k < nb; ++k)
        {
            SIZE_T row = (bands[k].right - bands[k].left) * sizeof(WORD);

            hdr->rects[k] = bands[k];
            for (y = bands[k].top; y < bands[k].bottom; ++y, dst += row)
                memcpy(dst, s->pbuf + y * s->pitch + bands[k].left * sizeof(WORD), row);
        }
        push(s->device, OP_EMIT, 0, 0, 0, hdr);
    }
    for (k = 0; k < nb; ++k)
        fill_key_buf(s, s->pbuf, &bands[k]);
}

/* Record the pending overlays of all surfaces. */
static void emit_record(void)
{
    int i;

    for (i = 0; i < MAX_SURF; ++i)
        if (surfs[i].iface && surfs[i].n_pend)
            emit_pending(&surfs[i]);
}

/* Called (through thunks) before anything that consumes or redirects a render target and is
 * not itself recorded. */
static void __cdecl emit_all(void)
{
    if (on_worker())
        return;
    emit_record();
    flush_batch();
}

/* Depth read-back. Once per frame, after the 3D scene, the game locks the whole depth buffer
 * read-only. A real lock has to wait until everything queued has been drawn and read back,
 * which stalls the game thread for a large part of every frame. Instead the game is handed a
 * copy made at the same point of the previous frame, and a command is queued that refreshes
 * the copy. Three buffers: the one the game holds, the newest complete one, and the one being
 * written. Measured +20% once the overlay uploads were out of the way (experiment 127); what
 * the game reads (it uses it for pointing at the battlefield) is one frame old.
 * D3D9LAZY_DEPTH=n refreshes on every n-th lock (default 1, 0 = real locks). Live: a file
 * d3d9lazy.nodepth in the game directory switches it off, d3d9lazy.depth2 sets n = 2. */

static void depth_refresh(IDirect3DSurface9 *iface)
{
    LONG pub = depth_published, held = depth_held, t;
    D3DLOCKED_RECT lr;

    for (t = 0; t == pub || t == held; ++t) ;
    if (SUCCEEDED(real_lock(iface, &lr, NULL, D3DLOCK_READONLY)))
    {
        if (lr.Pitch == depth_pitch)
        {
            memcpy(depth_buf[t], lr.pBits, depth_size);
            InterlockedExchange((LONG *)&depth_published, t);
        }
        real_unlock(iface);
    }
}

/* Play one recorded command into Direct3D. */
static void exec_cmd(const struct cmd *c)
{
    IDirect3DDevice9 *dev = c->dev;

    switch (c->op)
    {
        case OP_RS:
            real_set_rs(dev, c->a, c->b);
            break;
        case OP_TEX:
            real_set_tex(dev, c->a, c->p);
            if (c->p)
                IDirect3DBaseTexture9_Release((IDirect3DBaseTexture9 *)c->p);
            break;
        case OP_TSS:
            real_set_tss(dev, c->a, c->b, c->c);
            break;
        case OP_SAMP:
            real_set_samp(dev, c->a, c->b, c->c);
            break;
        case OP_FVF:
            real_set_fvf(dev, c->a);
            break;
        case OP_BEGIN:
            real_begin(dev);
            break;
        case OP_END:
            real_end(dev);
            break;
        case OP_DRAW:
            real_dipup(dev, D3DPT_TRIANGLELIST, 0, c->a, c->b / 3, c->p, D3DFMT_INDEX16,
                    (BYTE *)c->p + ((c->b * sizeof(WORD) + 15) & ~(SIZE_T)15), c->c);
            stream_dirty = TRUE;
            break;
        case OP_DRAWVB:
            if (stream_dirty || bound_vb != c->p || bound_stride != c->c)
            {
                real_set_stream(dev, 0, c->p, 0, c->c);
                bound_vb = c->p;
                bound_stride = c->c;
                stream_dirty = FALSE;
            }
            real_dp(dev, D3DPT_TRIANGLELIST, c->a, c->b);
            break;
        case OP_EMIT:
        {
            struct emit_hdr *hdr = c->p;

            if (!draw_overlays(hdr->s, hdr->rects, hdr->n, (const BYTE *)(hdr + 1)))
                InterlockedIncrement(&n_fail);
            stream_dirty = TRUE;
            break;
        }
        case OP_SETDS:
            real_set_ds(dev, c->p);
            if (c->p)
                IDirect3DSurface9_Release((IDirect3DSurface9 *)c->p);
            break;
        case OP_STRETCH:
        {
            struct stretch_args *st = c->p;

            real_stretch(dev, st->src, st->has_sr ? &st->sr : NULL, st->dst, st->has_dr ? &st->dr : NULL,
                    st->filter);
            IDirect3DSurface9_Release(st->src);
            IDirect3DSurface9_Release(st->dst);
            break;
        }
        case OP_DEPTHREAD:
            depth_refresh(c->p);
            IDirect3DSurface9_Release((IDirect3DSurface9 *)c->p);
            break;
        case OP_PRESENT:
            real_present(dev, NULL, NULL, NULL, NULL);
            InterlockedDecrement((LONG *)&presents_pending);
            break;
    }
}

/* A draw is about to be queued: if it could touch a pending overlay rectangle, the
 * overlay has to be drawn first. Screen-space (XYZRHW) vertices are tested exactly by
 * their bounding box; anything else counts as touching. */
static void check_draw_against_pending(IDirect3DDevice9 *dev, const void *verts, UINT nv, UINT stride)
{
    float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
    BOOL any = FALSE, hit = FALSE;
    DWORD fvf = 0;
    UINT i, k;
    int j;

    for (j = 0; j < MAX_SURF; ++j)
        if (surfs[j].iface && surfs[j].n_pend)
            any = TRUE;
    if (!any)
        return;
    if (filtering && dev == sh_dev && sh_fvf_ok)
        fvf = sh_fvf;
    else
    {
        flush_batch();
        if (SUCCEEDED(real_get_fvf(dev, &fvf)) && shadow_dev(dev))
        {
            sh_fvf = fvf;
            sh_fvf_ok = 1;
        }
    }
    if (!verts || stride < 8 || (fvf & D3DFVF_POSITION_MASK) != D3DFVF_XYZRHW)
        hit = TRUE;
    else
    {
        for (i = 0; i < nv; ++i)
        {
            const float *v = (const float *)((const BYTE *)verts + i * stride);
            if (v[0] < x0) x0 = v[0];
            if (v[0] > x1) x1 = v[0];
            if (v[1] < y0) y0 = v[1];
            if (v[1] > y1) y1 = v[1];
        }
        for (j = 0; j < MAX_SURF && !hit; ++j)
            for (k = 0; surfs[j].iface && k < surfs[j].n_pend; ++k)
            {
                const RECT *r = &surfs[j].pend[k];
                if (x0 < r->right + 1 && x1 > r->left - 1 && y0 < r->bottom + 1 && y1 > r->top - 1)
                    hit = TRUE;
            }
    }
    if (hit)
    {
        ++n_early;
        emit_record();
    }
}

static struct lazy_surf *find_surf(IDirect3DSurface9 *iface, BOOL create)
{
    D3DSURFACE_DESC desc;
    D3DLOCKED_RECT lr;
    struct lazy_surf *s, *free_slot = NULL;
    RECT full;
    int i;

    for (i = 0; i < MAX_SURF; ++i)
    {
        if (surfs[i].iface == iface)
            break;
        if (!surfs[i].iface && !free_slot)
            free_slot = &surfs[i];
    }
    s = i < MAX_SURF ? &surfs[i] : NULL;
    /* A tracked surface is trusted until Reset; asking Direct3D here would make the game
     * thread wait for whatever the helper thread is doing. */
    if (!create || s)
        return s;

    if (FAILED(IDirect3DSurface9_GetDesc(iface, &desc)) || !(desc.Usage & D3DUSAGE_RENDERTARGET)
            || desc.Format != D3DFMT_R5G6B5 || (desc.Width & 1))
        return NULL;
    if (s && s->width == desc.Width && s->height == desc.Height)
        return s;
    if (!s && !(s = free_slot))
        return NULL;

    /* New (or recreated) surface: learn the pitch with one real read-only lock. */
    flush_batch();
    if (s->buf)
        VirtualFree(s->buf, 0, MEM_RELEASE);
    if (s->pbuf)
        VirtualFree(s->pbuf, 0, MEM_RELEASE);
    memset(s, 0, sizeof(*s));
    if (FAILED(real_lock(iface, &lr, NULL, D3DLOCK_READONLY)))
        return NULL;
    real_unlock(iface);
    s->pitch = lr.Pitch;
    s->size = (SIZE_T)lr.Pitch * desc.Height;
    s->width = desc.Width;
    s->height = desc.Height;
    if (!(s->buf = VirtualAlloc(NULL, s->size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)))
        return NULL;
    if (!(s->pbuf = VirtualAlloc(NULL, s->size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)))
        return NULL;
    if (FAILED(IDirect3DSurface9_GetDevice(iface, &s->device)))
        return NULL;
    IDirect3DDevice9_Release(s->device);
    if (mode == MODE_OVERLAY && (!pool_ready || desc.Width > OVERLAY_SIZE || desc.Height > OVERLAY_SIZE))
    {
        if (n_fail++ < 3)
            log_line("d3d9lazy: no overlay texture for %ux%u\n", desc.Width, desc.Height);
        VirtualFree(s->buf, 0, MEM_RELEASE);
        s->buf = NULL;
        return NULL;
    }
    SetRect(&full, 0, 0, s->width, s->height);
    fill_key(s, &full);
    fill_key_buf(s, s->pbuf, &full);
    s->clean = TRUE;
    s->iface = iface;
    log_line("d3d9lazy: tracking render target %p %ux%u pitch %d\n", iface, desc.Width, desc.Height, lr.Pitch);
    return s;
}

static HRESULT WINAPI hook_lock(IDirect3DSurface9 *iface, D3DLOCKED_RECT *lr, const RECT *rect, DWORD flags)
{
    struct lazy_surf *s;

    /* The helper thread locks the shim's own textures; WineD3D routes that through here. */
    if (on_worker())
        return real_lock(iface, lr, rect, flags);
    mark(214);
    if (!rect && lr && !(flags & D3DLOCK_READONLY))
    {
        EnterCriticalSection(&cs);
        if ((s = find_surf(iface, TRUE)) && !s->locked)
        {
            s->locked = TRUE;
            lr->Pitch = s->pitch;
            lr->pBits = s->buf;
            LeaveCriticalSection(&cs);
            return D3D_OK;
        }
        LeaveCriticalSection(&cs);
    }
    if (!rect && lr && (flags & D3DLOCK_READONLY) && threading && depth_every && !depth_locked)
    {
        HRESULT hr;

        if (iface == depth_iface && depth_published >= 0)
        {
            InterlockedExchange((LONG *)&depth_held, depth_published);
            lr->Pitch = depth_pitch;
            lr->pBits = depth_buf[depth_held];
            depth_locked = TRUE;
            ++n_depth;
            if (++depth_count >= depth_every)
            {
                depth_count = 0;
                close_batch();
                IDirect3DSurface9_AddRef(iface);
                push(batch_dev, OP_DEPTHREAD, 0, 0, 0, iface);
            }
            return D3D_OK;
        }
        if (iface != not_depth_iface)
        {
            D3DSURFACE_DESC desc;

            /* First read-only lock of this surface: a real one, and remember what it is. */
            ++n_pass;
            emit_all();
            if (FAILED(IDirect3DSurface9_GetDesc(iface, &desc)) || !(desc.Usage & D3DUSAGE_DEPTHSTENCIL))
            {
                not_depth_iface = iface;
                return real_lock(iface, lr, rect, flags);
            }
            if (SUCCEEDED(hr = real_lock(iface, lr, rect, flags)))
            {
                int i;

                for (i = 0; i < 3; ++i)
                {
                    if (depth_buf[i])
                        VirtualFree(depth_buf[i], 0, MEM_RELEASE);
                    depth_buf[i] = NULL;
                }
                depth_pitch = lr->Pitch;
                depth_size = (SIZE_T)lr->Pitch * desc.Height;
                depth_published = depth_held = -1;
                depth_iface = NULL;
                for (i = 0; i < 3; ++i)
                    depth_buf[i] = VirtualAlloc(NULL, depth_size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
                if (depth_buf[0] && depth_buf[1] && depth_buf[2])
                {
                    memcpy(depth_buf[0], lr->pBits, depth_size);
                    depth_published = 0;
                    depth_iface = iface;
                    log_line("d3d9lazy: depth buffer %p %ux%u pitch %d served from copies\n", iface,
                            desc.Width, desc.Height, lr->Pitch);
                }
                else
                    not_depth_iface = iface;
            }
            return hr;
        }
    }
    ++n_pass;
    emit_all();
    return real_lock(iface, lr, rect, flags);
}

static HRESULT WINAPI hook_unlock(IDirect3DSurface9 *iface)
{
    struct lazy_surf *s;
    UINT count;
    RECT r;

    if (on_worker())
        return real_unlock(iface);
    mark(216);
    if (depth_locked && iface == depth_iface)
    {
        depth_locked = FALSE;
        return D3D_OK;
    }
    EnterCriticalSection(&cs);
    if ((s = find_surf(iface, FALSE)) && s->locked)
    {
        s->locked = FALSE;
        ++n_windows;
        if (find_changes(s, &r, &count))
        {
            ++n_written;
            n_pixels += count;
            if (n_written <= 40 || !(n_written % 500))
                log_line("d3d9lazy: window %ld changed (%ld,%ld)-(%ld,%ld) about %u px\n",
                        n_windows, r.left, r.top, r.right, r.bottom, count);
            /* Move the changed pixels to the pending buffer. */
            {
                LONG y, x;

                if (s->n_pend == MAX_PEND)
                    emit_pending(s);
                for (y = r.top; y < r.bottom; ++y)
                {
                    WORD *src = (WORD *)(s->buf + y * s->pitch), *dst = (WORD *)(s->pbuf + y * s->pitch);
                    for (x = r.left; x < r.right; ++x)
                        if (src[x] != KEY16)
                        {
                            dst[x] = src[x];
                            src[x] = KEY16;
                        }
                }
                s->pend[s->n_pend++] = r;
                if (!deferring)
                    emit_pending(s);
            }
        }
        if (!(n_windows % 2000))
            log_line("d3d9lazy: windows %ld written %ld pixels %ld passthrough %ld failed %ld"
                    " draws in %ld out %ld unbatched %ld emits %ld bands %ld early %ld states %ld skipped %ld cmds %ld syncs %ld groups %ld vbdraws %ld depth %ld cache %ld/%ld\n",
                    n_windows, n_written, (long)n_pixels, n_pass, n_fail,
                    n_draws_in, n_draws_out, n_draws_pass, n_emits, n_bands, n_early, n_state, n_state_skip, n_cmds, n_sync, n_groups, n_vb_draws, n_depth, n_cache_hit, n_cache_miss);
        LeaveCriticalSection(&cs);
        return D3D_OK;
    }
    LeaveCriticalSection(&cs);
    flush_batch();
    return real_unlock(iface);
}

static void patch(void **slot, void *value)
{
    DWORD old;
    VirtualProtect(slot, sizeof(*slot), PAGE_READWRITE, &old);
    *slot = value;
    VirtualProtect(slot, sizeof(*slot), old, &old);
}

/* Device methods that consume or redirect a render target: pending overlays first. */
static BOOL is_consumer(UINT slot)
{
#define SLOT(m) (offsetof(IDirect3DDevice9Vtbl, m) / sizeof(void *))
    static const UINT list[] =
    {
        SLOT(Present), SLOT(StretchRect), SLOT(SetRenderTarget), SLOT(Clear), SLOT(ColorFill),
        SLOT(UpdateSurface), SLOT(UpdateTexture), SLOT(GetRenderTargetData), SLOT(GetFrontBufferData),
        SLOT(SetDepthStencilSurface), SLOT(SetViewport), SLOT(SetScissorRect),
        SLOT(CreateAdditionalSwapChain), SLOT(EvictManagedResources),
    };
#undef SLOT
    UINT i;

    for (i = 0; i < COUNT(list); ++i)
        if (list[i] == slot)
            return TRUE;
    return FALSE;
}

static HRESULT WINAPI hook_create_device(IDirect3D9 *d3d, UINT adapter, D3DDEVTYPE type, HWND window,
        DWORD behaviour, D3DPRESENT_PARAMETERS *pp, IDirect3DDevice9 **device)
{
    IDirect3DSurface9 *bb;
    HRESULT hr;

    hr = real_create_device(d3d, adapter, type, window, behaviour, pp, device);
    if (SUCCEEDED(hr) && !real_lock
            && SUCCEEDED(IDirect3DDevice9_GetBackBuffer(*device, 0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)))
    {
        real_lock = bb->lpVtbl->LockRect;
        real_unlock = bb->lpVtbl->UnlockRect;
        patch((void **)&bb->lpVtbl->LockRect, hook_lock);
        patch((void **)&bb->lpVtbl->UnlockRect, hook_unlock);
        IDirect3DSurface9_Release(bb);
        log_line("d3d9lazy: surface LockRect/UnlockRect hooked\n");
    }
    if (SUCCEEDED(hr) && mode == MODE_OVERLAY && !pool_ready)
    {
        UINT c, i, failed = 0;

        for (c = 0; c < POOL_CLASSES; ++c)
            for (i = 0; i < pool_count[c]; ++i)
                if (FAILED(IDirect3DDevice9_CreateTexture(*device, pool_w[c], pool_h[c], 1, 0,
                        D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &pool[c][i], NULL)))
                    ++failed;
        pool_ready = !failed;
        log_line("d3d9lazy: overlay texture pool created, %u failures\n", failed);
    }
    if (SUCCEEDED(hr) && batching && !real_dpup)
    {
        void **vtbl = (void **)(*device)->lpVtbl;
        UINT n = sizeof(IDirect3DDevice9Vtbl) / sizeof(void *), i;
        UINT i_dpup = offsetof(IDirect3DDevice9Vtbl, DrawPrimitiveUP) / sizeof(void *);
        UINT i_dipup = offsetof(IDirect3DDevice9Vtbl, DrawIndexedPrimitiveUP) / sizeof(void *);
        IDirect3DTexture9 *tex = NULL;
        void *real_sb[3], *real_fv[2];

        batch_verts = VirtualAlloc(NULL, BATCH_MAX_VERTS * BATCH_MAX_STRIDE, MEM_COMMIT | MEM_RESERVE,
                PAGE_READWRITE);
        batch_idx = VirtualAlloc(NULL, BATCH_MAX_IDX * sizeof(WORD), MEM_COMMIT | MEM_RESERVE,
                PAGE_READWRITE);
        if (batch_verts && batch_idx)
        {
            real_dpup = vtbl[i_dpup];
            real_dipup = vtbl[i_dipup];
#define SLOT(m) (offsetof(IDirect3DDevice9Vtbl, m) / sizeof(void *))
            real_reset = vtbl[SLOT(Reset)];
            real_get_fvf = vtbl[SLOT(GetFVF)];
            real_set_stream = vtbl[SLOT(SetStreamSource)];
            real_dp = vtbl[SLOT(DrawPrimitive)];
            real_create_vb = vtbl[SLOT(CreateVertexBuffer)];
            real_begin = vtbl[SLOT(BeginScene)];
            real_end = vtbl[SLOT(EndScene)];
            real_set_ds = vtbl[SLOT(SetDepthStencilSurface)];
            real_stretch = vtbl[SLOT(StretchRect)];
            real_present = vtbl[SLOT(Present)];
            real_get_bb = vtbl[SLOT(GetBackBuffer)];
            real_get_tss = vtbl[SLOT(GetTextureStageState)];
            real_set_rs = vtbl[SLOT(SetRenderState)];
            real_set_tex = vtbl[SLOT(SetTexture)];
            real_set_tss = vtbl[SLOT(SetTextureStageState)];
            real_set_samp = vtbl[SLOT(SetSamplerState)];
            real_set_fvf = vtbl[SLOT(SetFVF)];
            real_sb[0] = vtbl[SLOT(CreateStateBlock)];
            real_sb[1] = vtbl[SLOT(BeginStateBlock)];
            real_sb[2] = vtbl[SLOT(EndStateBlock)];
            real_fv[0] = vtbl[SLOT(SetVertexDeclaration)];
            real_fv[1] = vtbl[SLOT(SetVertexShader)];
            /* Everything except QueryInterface/AddRef/Release and the two batched draws
             * flushes the batch first. */
            for (i = 3; i < n; ++i)
                if (i != i_dpup && i != i_dipup)
                    patch(&vtbl[i], make_thunk(vtbl[i], is_consumer(i) ? th_emit : th_flush, i));
            patch(&vtbl[i_dpup], hook_dpup);
            patch(&vtbl[i_dipup], hook_dipup);
            patch(&vtbl[SLOT(Reset)], hook_reset);
            if (!(arena = VirtualAlloc(NULL, ARENA_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)))
                ExitProcess(1);
            if (threading && !CreateThread(NULL, 0, worker_proc, NULL, 0, &worker_tid))
                threading = FALSE;
            thread_ok = threading;
            log_line("d3d9lazy: command thread %s\n", threading ? "on" : "off");
            patch(&vtbl[SLOT(SetStreamSource)], make_thunk(real_set_stream, th_stream, SLOT(SetStreamSource)));
            patch(&vtbl[SLOT(BeginScene)], hook_begin);
            patch(&vtbl[SLOT(EndScene)], hook_end);
            patch(&vtbl[SLOT(SetDepthStencilSurface)], hook_set_ds);
            patch(&vtbl[SLOT(StretchRect)], hook_stretch);
            patch(&vtbl[SLOT(Present)], hook_present);
            patch(&vtbl[SLOT(GetBackBuffer)], hook_get_bb);
            patch(&vtbl[SLOT(GetTextureStageState)], hook_get_tss);
            patch(&vtbl[SLOT(SetRenderState)], hook_set_rs);
            patch(&vtbl[SLOT(SetTexture)], hook_set_tex);
            patch(&vtbl[SLOT(SetTextureStageState)], hook_set_tss);
            patch(&vtbl[SLOT(SetSamplerState)], hook_set_samp);
            patch(&vtbl[SLOT(SetFVF)], hook_set_fvf);
            {
                static const UINT off_slots[] = {SLOT(CreateStateBlock), SLOT(BeginStateBlock),
                        SLOT(EndStateBlock)};
                static const UINT fvf_slots[] = {SLOT(SetVertexDeclaration), SLOT(SetVertexShader)};

                for (i = 0; i < COUNT(off_slots); ++i)
                    patch(&vtbl[off_slots[i]], make_thunk(real_sb[i], th_off, off_slots[i]));
                for (i = 0; i < COUNT(fvf_slots); ++i)
                    patch(&vtbl[fvf_slots[i]], make_thunk(real_fv[i], th_fvf, fvf_slots[i]));
            }
#undef SLOT
            /* The game may rewrite a texture that pending draws use. The shim's own calls
             * go through the same thunk, which is harmless. */
            if (SUCCEEDED(IDirect3DDevice9_CreateTexture(*device, 16, 16, 1, 0, D3DFMT_A8R8G8B8,
                    D3DPOOL_MANAGED, &tex, NULL)))
            {
                patch((void **)&tex->lpVtbl->LockRect, make_thunk(tex->lpVtbl->LockRect, th_flush, 120));
                IDirect3DTexture9_Release(tex);
            }
            log_line("d3d9lazy: draw batching on, %u device methods thunked\n", n - 5);
        }
        else
            batching = FALSE;
    }
    return hr;
}

IDirect3D9 * WINAPI Direct3DCreate9(UINT sdk_version)
{
    IDirect3D9 *d3d;

    if (!real_create9)
        return NULL;
    d3d = real_create9(sdk_version);
    if (d3d && mode != MODE_OFF && !real_create_device)
    {
        real_create_device = d3d->lpVtbl->CreateDevice;
        patch((void **)&d3d->lpVtbl->CreateDevice, hook_create_device);
    }
    return d3d;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, void *reserved)
{
    char path[MAX_PATH], env[16];
    int i;

    if (reason == DLL_PROCESS_ATTACH)
    {
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&cs);
        QueryPerformanceFrequency(&qpc_freq);
        QueryPerformanceCounter(&qpc_start);
        for (i = 0; i < OVERLAY_SIZE / 2; ++i)
            key_row[i] = KEY32;
        if (GetEnvironmentVariableA("D3D9LAZY", env, sizeof(env)))
        {
            if (env[0] == '0') mode = MODE_OFF;
            else if (env[0] == 'p') mode = MODE_PROBE;
        }
        if (GetEnvironmentVariableA("D3D9LAZY_LOG", env, sizeof(env)) && env[0] == '1')
            logging = TRUE;
        if (GetEnvironmentVariableA("D3D9LAZY_BATCH", env, sizeof(env)) && env[0] == '0')
            batching = FALSE;
        if (GetEnvironmentVariableA("D3D9LAZY_DEFER", env, sizeof(env)) && env[0] == '0')
            deferring = FALSE;
        if (GetEnvironmentVariableA("D3D9LAZY_FILTER", env, sizeof(env)) && env[0] == '0')
            filtering = FALSE;
        if (GetEnvironmentVariableA("D3D9LAZY_THREAD", env, sizeof(env)) && env[0] == '0')
            threading = FALSE;
        if (GetEnvironmentVariableA("D3D9LAZY_DEPTH", env, sizeof(env)) && env[0] >= '0' && env[0] <= '9')
            depth_every = depth_env = env[0] - '0';
        if (GetEnvironmentVariableA("D3D9LAZY_VB", env, sizeof(env)) && env[0] == '0')
            vb_allowed = use_vb = FALSE;
        GetSystemDirectoryA(path, sizeof(path) - 16);
        strcat(path, "\\d3d9.dll");
        if ((real_d3d9 = LoadLibraryA(path)))
            real_create9 = (void *)GetProcAddress(real_d3d9, "Direct3DCreate9");
        log_line("d3d9lazy: loaded, real d3d9 %p, mode %d\n", real_d3d9, mode);
    }
    return TRUE;
}
