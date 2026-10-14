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
    static synchronized String token(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("pairing", MODE_PRIVATE);
        String value = prefs.getString("token", null);
        if (value == null) {
            byte[] bytes = new byte[16]; new SecureRandom().nextBytes(bytes);
            StringBuilder b = new StringBuilder(); for (byte v : bytes) b.append(String.format("%02x", v & 255));
            value = b.toString(); prefs.edit().putString("token", value).apply();
        }
        return value;
    }
    static synchronized String deviceId(Context context) {
        android.content.SharedPreferences prefs = context.getSharedPreferences("pairing", MODE_PRIVATE);
        String id = prefs.getString("device_id", null);
        if (id == null) { id = java.util.UUID.randomUUID().toString(); prefs.edit().putString("device_id", id).apply(); }
        return id;
    }
    private final android.os.Handler ui = new android.os.Handler(android.os.Looper.getMainLooper());
    private TextView status;
    private final Runnable refresh = new Runnable() { public void run() { updateStatus(); ui.postDelayed(this,1000); }};
    private void updateStatus() {
        EdgeService service = EdgeService.instance;
        boolean online = service != null && service.connected();
        String wifi;
        try { wifi = Settings.Global.getInt(getContentResolver(), "adb_wifi_enabled", 0) == 1 ? "On — advertised automatically to your Mac" : "Off — open Developer options below"; }
        catch (SecurityException e) { wifi = "Check in Developer options"; }
        status.setText((online ? "Connected to your Mac" : "Ready to connect") + "\nAccessibility: " + (service != null ? "Enabled" : "Needs setup") + "\nWireless debugging: " + wifi);
        if (getSharedPreferences("pairing", MODE_PRIVATE).getBoolean("keep_awake", true) && online)
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }
    private void settings(String action) {
        try { startActivity(new Intent(action)); }
        catch (android.content.ActivityNotFoundException e) { Toast.makeText(this,"Open this setting in Android Settings.",Toast.LENGTH_LONG).show(); }
    }
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        ScrollView scroll = new ScrollView(this);
        LinearLayout layout = new LinearLayout(this); layout.setOrientation(LinearLayout.VERTICAL); layout.setPadding(40,60,40,40);
        TextView title = new TextView(this); title.setText("Android Control Companion"); title.setTextSize(27); layout.addView(title);
        status = new TextView(this); status.setTextSize(18); status.setPadding(0,24,0,24); layout.addView(status);
        TextView help = new TextView(this); help.setText("1. Enable this companion in Accessibility.\n2. Use the same Wi-Fi as your Mac. Turn on Wireless debugging in Developer options and pair the Mac once. USB also works.\n3. Choose your phone and Connect in the Mac app. The companion code is supplied automatically over your authorized connection.\n"); help.setTextSize(17); layout.addView(help);
        Button enable = new Button(this); enable.setText("Open Accessibility settings"); enable.setOnClickListener(v -> settings(Settings.ACTION_ACCESSIBILITY_SETTINGS)); layout.addView(enable);
        Button wireless = new Button(this); wireless.setText("Set up Wireless debugging"); wireless.setOnClickListener(v -> settings(Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS)); layout.addView(wireless);
        Button keyboard = new Button(this); keyboard.setText("Match physical keyboard layout");
        keyboard.setOnClickListener(v -> settings(Settings.ACTION_HARD_KEYBOARD_SETTINGS)); layout.addView(keyboard);
        TextView keyboardHelp = new TextView(this);
        keyboardHelp.setText("While connected, select UCA Keyboard and choose the layout matching your Mac (for example English (US)). Set the same physical layout for each typing language. A different layout can turn ? into _."); layout.addView(keyboardHelp);
        Switch awake = new Switch(this); awake.setText("Keep screen awake while connected"); awake.setChecked(getSharedPreferences("pairing", MODE_PRIVATE).getBoolean("keep_awake", true));
        awake.setOnCheckedChangeListener((button, checked) -> {
            getSharedPreferences("pairing", MODE_PRIVATE).edit().putBoolean("keep_awake", checked).apply();
            if (EdgeService.instance != null) EdgeService.instance.refreshAwake(); updateStatus();
        }); layout.addView(awake);
        TextView awakeHelp = new TextView(this); awakeHelp.setText("Prevents idle sleep while connected, including in other apps. A small blue dot indicates the screen-awake hold. Disconnecting restores normal sleep. The power button still locks your phone."); layout.addView(awakeHelp);
        Button stop = new Button(this); stop.setText("Disconnect Mac"); stop.setOnClickListener(v -> { if (EdgeService.instance != null) EdgeService.instance.disconnectClient(); updateStatus(); }); layout.addView(stop);
        TextView code = new TextView(this); code.setText(token(this)); code.setTextIsSelectable(true); code.setTextSize(18); code.setVisibility(android.view.View.GONE); layout.addView(code);
        Button show = new Button(this); show.setText("Show code for manual setup"); show.setOnClickListener(v -> { boolean hidden=code.getVisibility()!=android.view.View.VISIBLE; code.setVisibility(hidden ? android.view.View.VISIBLE : android.view.View.GONE); show.setText(hidden ? "Hide code" : "Show code for manual setup"); }); layout.addView(show);
        Button rotate = new Button(this); rotate.setText("Reset companion code and disconnect"); rotate.setOnClickListener(v -> {
            getSharedPreferences("pairing", MODE_PRIVATE).edit().remove("token").apply();
            if (EdgeService.instance != null) EdgeService.instance.disconnectClient();
            code.setText(token(this)); updateStatus();
        }); layout.addView(rotate);
        TextView note = new TextView(this); note.setText("Android requires you to approve debugging and Accessibility. If a network change disables Wireless debugging, enable it again here. Resetting the companion code does not revoke debugging access: forget the Mac in Wireless debugging to revoke that pairing.\n\nNo screen reading or keyboard logging. Keep your manual code private."); layout.addView(note);
        scroll.addView(layout); setContentView(scroll);
    }
    @Override protected void onResume() { super.onResume(); ui.post(refresh); }
    @Override protected void onPause() { ui.removeCallbacks(refresh); super.onPause(); }
}
