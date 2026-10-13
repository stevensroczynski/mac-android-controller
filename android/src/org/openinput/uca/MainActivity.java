package org.openinput.uca;

import android.app.Activity;
import android.os.Bundle;
import android.content.Intent;
import android.provider.Settings;
import android.view.WindowManager;
import android.widget.*;
import android.content.Context;
import java.security.SecureRandom;

public final class MainActivity extends Activity {
    static String token(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("pairing", MODE_PRIVATE);
        String value = prefs.getString("token", null);
        if (value == null) {
            byte[] bytes = new byte[16]; new SecureRandom().nextBytes(bytes);
            StringBuilder b = new StringBuilder(); for (byte v : bytes) b.append(String.format("%02x", v & 255));
            value = b.toString(); prefs.edit().putString("token", value).apply();
        }
        return value;
    }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(40,60,40,40);
        TextView title = new TextView(this); title.setText("Return to your Mac"); title.setTextSize(28); layout.addView(title);
        TextView help = new TextView(this); help.setText("1. Enable this app in Accessibility settings.\n2. Enable USB debugging and authorize your Mac.\n3. Enter this code in the Mac app.\n\nThe code grants edge detection and Back/Home/Recents control. Keep it private. No internet permission, screen reading, or keyboard logging.\n"); help.setTextSize(17); layout.addView(help);
        TextView code = new TextView(this); code.setText(token(this)); code.setTextIsSelectable(true); code.setTextSize(19); layout.addView(code);
        Button enable = new Button(this); enable.setText("Open Accessibility settings"); enable.setOnClickListener(v -> startActivity(new Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))); layout.addView(enable);
        Button rotate = new Button(this); rotate.setText("Reset pairing code and stop sharing"); rotate.setOnClickListener(v -> {
            getSharedPreferences("pairing", MODE_PRIVATE).edit().remove("token").apply();
            if (EdgeService.instance != null) EdgeService.instance.disconnectClient();
            code.setText(token(this));
        }); layout.addView(rotate);
        TextView note = new TextView(this); note.setText("If Android blocks Accessibility for a sideloaded app, open App info → menu → Allow restricted settings first.\n\nThe thin return strip appears only during sharing. Disable this Accessibility service to stop it entirely."); layout.addView(note);
        setContentView(layout);
    }
}
