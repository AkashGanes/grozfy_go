package com.lyncspace.grozfygo;

import android.content.Intent;
import android.util.Log;
import io.flutter.embedding.android.FlutterFragmentActivity;

public final class MainActivity extends FlutterFragmentActivity {
    @Override
    public void onActivityResult(int requestCode, int resultCode, Intent data) {
        try {
            super.onActivityResult(requestCode, resultCode, data);
        } catch (IllegalStateException e) {
            // image_cropper plugin bug: fires onActivityResult twice when crop is
            // cancelled, causing "Reply already submitted" on the second delivery.
            Log.w("MainActivity", "Ignored duplicate activity result: " + e.getMessage());
        }
    }
}
