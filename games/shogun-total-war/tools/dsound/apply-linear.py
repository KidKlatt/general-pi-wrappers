"""Apply the STW linear-resampler change to Wine 9.17's dlls/dsound (run inside that folder).

Wine's DirectSound resamples every secondary buffer whose rate differs from the mix rate with a
FIR filter (fir.h: 7907 points, step 120, so about 66 taps per output sample and channel, plus
re-interpolating the taps for every sample). Under x86 emulation on a Raspberry Pi 4 this one
loop takes a whole core in battles of Shogun: Total War (22050/11025 Hz sounds mixed at 48 kHz)
and the game waits for it (experiments in EXPERIMENTS.md, 2026-11-17).

This build uses linear interpolation instead. STW_DSOUND_RESAMPLER=fir in the environment
restores the original filter, so both can be compared with the same DLL.
"""
import pathlib

def sub(path, old, new):
    p = pathlib.Path(path)
    s = p.read_text()
    assert old in s, (path, old[:60])
    p.write_text(s.replace(old, new, 1))

sub("dsound_private.h", "extern int ds_hel_buflen;\n",
    "extern int ds_hel_buflen;\nextern int ds_linear_resample;\n")

sub("dsound_main.c", "int ds_hel_buflen = 32768 * 2;\n",
    "int ds_hel_buflen = 32768 * 2;\n"
    "/* STW build: linear resampling instead of the FIR filter (see mixer.c). */\n"
    "int ds_linear_resample = 1;\n")

sub("dsound_main.c", '    TRACE("ds_hel_buflen = %d\\n", ds_hel_buflen);\n',
    '    TRACE("ds_hel_buflen = %d\\n", ds_hel_buflen);\n'
    '\n'
    '    if (GetEnvironmentVariableA("STW_DSOUND_RESAMPLER", buffer, MAX_PATH) && !strcmp(buffer, "fir"))\n'
    '        ds_linear_resample = 0;\n'
    '    ERR("STW dsound build: %s resampler\\n", ds_linear_resample ? "linear" : "fir");\n')

LINEAR = r'''
/* STW build: linear interpolation between the two nearest input samples. About 66 times less
 * work per output sample than the FIR path below; slightly duller high frequencies. */
static UINT cp_fields_resample_linear(IDirectSoundBufferImpl *dsb, UINT count, LONG64 *freqAccNum)
{
    UINT i, channel;
    UINT istride = dsb->pwfx->nBlockAlign;
    UINT ostride = dsb->device->pwfx->nChannels * sizeof(float);
    UINT committed_samples = 0;
    LONG64 freqAcc_start = *freqAccNum;
    LONG64 freqAcc_end = freqAcc_start + count * dsb->freqAdjustNum;
    UINT channels = dsb->mix_channels;
    UINT max_ipos = freqAcc_end / dsb->freqAdjustDen;
    UINT required_input = max_ipos + 2;
    float *intermediate, *itmp;
    DWORD len = required_input * channels * sizeof(float);

    *freqAccNum = freqAcc_end % dsb->freqAdjustDen;

    if (!secondarybuffer_is_audible(dsb))
        return max_ipos;

    if (!dsb->device->cp_buffer) {
        dsb->device->cp_buffer = malloc(len);
        dsb->device->cp_buffer_len = len;
    } else if (len > dsb->device->cp_buffer_len) {
        dsb->device->cp_buffer = realloc(dsb->device->cp_buffer, len);
        dsb->device->cp_buffer_len = len;
    }
    intermediate = dsb->device->cp_buffer;

    if (dsb->use_committed) {
        committed_samples = (dsb->writelead - dsb->committed_mixpos) / istride;
        committed_samples = committed_samples <= required_input ? committed_samples : required_input;
    }

    itmp = intermediate;
    for (channel = 0; channel < channels; channel++) {
        for (i = 0; i < committed_samples; i++)
            *(itmp++) = get_current_sample(dsb, dsb->committedbuff,
                dsb->writelead, dsb->committed_mixpos + i * istride, channel);
        for (; i < required_input; i++)
            *(itmp++) = get_current_sample(dsb, dsb->buffer->memory,
                    dsb->buflen, dsb->sec_mixpos + i * istride, channel);
    }

    for (i = 0; i < count; ++i) {
        LONG64 acc = freqAcc_start + i * dsb->freqAdjustNum;
        UINT ipos = acc / dsb->freqAdjustDen;
        float rem = (float)(acc % dsb->freqAdjustDen) / (float)dsb->freqAdjustDen;

        for (channel = 0; channel < channels; channel++) {
            const float *cache = &intermediate[channel * required_input + ipos];
            dsb->put(dsb, i * ostride, channel, cache[0] + (cache[1] - cache[0]) * rem);
        }
    }

    return max_ipos;
}

'''
ANCHOR = "static void cp_fields(IDirectSoundBufferImpl *dsb, UINT count, LONG64 *freqAccNum)"
sub("mixer.c", ANCHOR, LINEAR + ANCHOR)
sub("mixer.c", "        adv = cp_fields_resample(dsb, count, freqAccNum);",
    "        adv = ds_linear_resample ? cp_fields_resample_linear(dsb, count, freqAccNum)\n"
    "                                 : cp_fields_resample(dsb, count, freqAccNum);")
print("patched")
