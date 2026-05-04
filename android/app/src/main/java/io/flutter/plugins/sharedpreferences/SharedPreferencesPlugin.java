package io.flutter.plugins.sharedpreferences;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Shim for Flutter's generated Android registrant.
 *
 * The current toolchain generates a reference to SharedPreferencesPlugin, but
 * the plugin dependency is not exposing that class to the app's Java compile
 * step in this project. Delegating to the legacy implementation keeps the
 * platform channel registration working for the synchronous API used here.
 */
public final class SharedPreferencesPlugin implements FlutterPlugin {
  private final LegacySharedPreferencesPlugin delegate = new LegacySharedPreferencesPlugin();

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    delegate.onAttachedToEngine(binding);
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    delegate.onDetachedFromEngine(binding);
  }
}
