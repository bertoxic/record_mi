package com.example.record_mi;

import android.os.ParcelFileDescriptor;

interface ICallRecorderService {
    boolean startRecording(in ParcelFileDescriptor outputPfd);
    boolean startRecordingWithOptions(in ParcelFileDescriptor outputPfd, String callType, int preferredSource);
    void stopRecording();
    boolean isRecording();
    boolean setSpeakerphone(boolean on);
    boolean isSpeakerphoneOn();
    boolean isVoipRecordingActive();
    void destroy();
}
