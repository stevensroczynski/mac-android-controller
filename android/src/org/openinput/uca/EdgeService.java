package org.openinput.uca;

import android.accessibilityservice.AccessibilityService;
import android.view.accessibility.AccessibilityEvent;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.graphics.PixelFormat;
import android.view.*;
import android.content.res.Configuration;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.concurrent.*;

public final class EdgeService extends AccessibilityService {
    static volatile EdgeService instance;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService writer = new ThreadPoolExecutor(1,1,0,TimeUnit.MILLISECONDS,new ArrayBlockingQueue<Runnable>(32));
    private volatile boolean running;
    private volatile LocalSocket client;
    private LocalServerSocket server;
    private volatile BufferedWriter output;
    private View strip;
    private View awakeIndicator;
    private volatile boolean authenticated;
    private volatile String lastDisconnect = "none";
    private volatile android.os.PowerManager.WakeLock awake;
    private String edge;
    private long armedAt;
    private int failures;
    private long blockedUntil;
    private volatile long lastMessage;
    private final Runnable watchdog = new Runnable() { public void run() {
        if (!running) return;
        if (client != null && SystemClock.elapsedRealtime() - lastMessage > 4000) disconnectClient("heartbeat_timeout");
        refreshAwake();
        main.postDelayed(this, 1000);
    }};
    @Override protected void onServiceConnected() {
        instance = this;
        if (running) return;
        running = true; main.post(watchdog);
        new Thread(this::serve, "edge-notifications").start();
    }
    private void serve() {
        try {
            server = new LocalServerSocket("uca-edge-v1");
            while (running) {
                LocalSocket socket = server.accept();
                if (SystemClock.elapsedRealtime() < blockedUntil) { socket.close(); continue; }
                client = socket; lastMessage = SystemClock.elapsedRealtime(); socket.setSoTimeout(4000);
                try {
                    InputStream input = socket.getInputStream();
                    String auth = line(input);
                    String expected = "AUTH " + MainActivity.token(this);
                    if (!MessageDigest.isEqual(expected.getBytes(StandardCharsets.UTF_8), auth.getBytes(StandardCharsets.UTF_8))) {
                        if (++failures >= 5) { blockedUntil = SystemClock.elapsedRealtime()+60000; failures = 0; }
                        continue;
                    }
                    failures = 0; authenticated = true; main.post(this::refreshAwake);
                    output = new BufferedWriter(new OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8));
                    send("OK", socket);
                    long window = SystemClock.elapsedRealtime(); int messages = 0;
                    while (running && client == socket) {
                        String command = line(input); lastMessage = SystemClock.elapsedRealtime();
                        if (lastMessage-window >= 1000) { window=lastMessage; messages=0; }
                        if (++messages>30) throw new IOException("Rate limit");
                        if (command.equals("PING")) send("PONG", socket);
                        else if (command.equals("DISARM")) main.post(() -> { if (client == socket) removeStrip(); });
                        else if (command.matches("ARM (LEFT|RIGHT|TOP|BOTTOM)")) main.post(() -> { if (client == socket) arm(command.substring(4), socket); });
                        else if (command.equals("BACK") || command.equals("HOME") || command.equals("RECENTS")) main.post(() -> {
                            if (client == socket) performGlobalAction(command.equals("BACK") ? GLOBAL_ACTION_BACK : command.equals("HOME") ? GLOBAL_ACTION_HOME : GLOBAL_ACTION_RECENTS);
                        });
                        else throw new IOException("Invalid command");
                    }
                } catch (IOException error) {
                    if (client == socket) disconnectClient(error instanceof EOFException ? "host_closed" : "socket_read_failed");
                }
                finally { if (client == socket) disconnectClient(); else try { socket.close(); } catch (IOException ignored) {} }
            }
        } catch (IOException ignored) { main.post(this::disableSelf); }
    }
    // Strict bound: an untrusted local client cannot grow an unbounded line buffer.
    private static String line(InputStream input) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        for (int i=0; i<128; i++) { int c=input.read(); if(c<0) throw new EOFException(); if(c==10) return b.toString("UTF-8"); if(c<32 || c>126) throw new IOException("Invalid byte"); b.write(c); }
        throw new IOException("Line too long");
    }
    private void send(String message, LocalSocket socket) {
        try { writer.execute(() -> { try { BufferedWriter current = output; if (client == socket && current != null) { current.write(message); current.newLine(); current.flush(); } } catch (IOException ignored) { if (client == socket) disconnectClient(); } }); }
        catch (RejectedExecutionException ignored) { if (client == socket) disconnectClient(); }
    }
    private void arm(String side, LocalSocket socket) {
        removeStrip(); edge = side; armedAt = SystemClock.elapsedRealtime();
        View view = new View(this); strip = view;
        view.setBackgroundColor(0x223b82f6);
        int thickness = Math.max(8, (int)(8 * getResources().getDisplayMetrics().density));
        boolean vertical = side.equals("LEFT") || side.equals("RIGHT");
        WindowManager.LayoutParams params = new WindowManager.LayoutParams(vertical ? thickness : -1, vertical ? -1 : thickness,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        params.gravity = side.equals("LEFT") ? Gravity.LEFT : side.equals("RIGHT") ? Gravity.RIGHT : side.equals("TOP") ? Gravity.TOP : Gravity.BOTTOM;
        params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        view.setOnHoverListener((v, event) -> {
            if (client == socket && (event.getSource() & InputDevice.SOURCE_MOUSE) == InputDevice.SOURCE_MOUSE &&
                (event.getActionMasked() == MotionEvent.ACTION_HOVER_ENTER || event.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) &&
                SystemClock.elapsedRealtime() - armedAt > 450) {
                send("RETURN", socket); removeStrip();
            }
            return true;
        });
        try { ((WindowManager)getSystemService(WINDOW_SERVICE)).addView(view, params); send("ARMED", socket); }
        catch (RuntimeException error) { disconnectClient(); }
    }
    private void removeStrip() {
        if (strip != null) { try { ((WindowManager)getSystemService(WINDOW_SERVICE)).removeView(strip); } catch (RuntimeException ignored) {} strip = null; }
        edge = null;
    }
    String disconnectReason() { return lastDisconnect; }
    long idleMillis() { return SystemClock.elapsedRealtime() - lastMessage; }
    boolean awakeHeld() { return awakeIndicator != null && awakeIndicator.isAttachedToWindow(); }
    boolean connected() { return authenticated && client != null; }
    @SuppressWarnings("deprecation")
    void refreshAwake() {
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post(this::refreshAwake); return; }
        android.os.PowerManager power = (android.os.PowerManager)getSystemService(POWER_SERVICE);
        android.app.KeyguardManager keyguard = (android.app.KeyguardManager)getSystemService(KEYGUARD_SERVICE);
        if (connected() && (!power.isInteractive() || keyguard.isKeyguardLocked())) {
            disconnectClient("phone_locked"); return; // Never wake or unlock a manually locked phone.
        }
        boolean keep = connected() && getSharedPreferences("pairing", MODE_PRIVATE).getBoolean("keep_awake", true);
        if (keep) {
            // A visible window requests a display-scoped screen hold, including
            // when another app is foreground. A legacy screen wake lock alone
            // was insufficient on the physical wireless test device.
            if (awakeIndicator == null) {
                View indicator = new View(this);
                indicator.setContentDescription("Mac connected — screen kept awake");
                indicator.setBackgroundColor(0xff3b82f6);
                int size = Math.max(4, (int)(6 * getResources().getDisplayMetrics().density));
                WindowManager.LayoutParams params = new WindowManager.LayoutParams(size, size,
                    WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE | WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE |
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                    PixelFormat.TRANSLUCENT);
                params.gravity = Gravity.TOP | Gravity.END;
                params.setTitle("UCA connected awake indicator");
                try {
                    ((WindowManager)getSystemService(WINDOW_SERVICE)).addView(indicator, params);
                    awakeIndicator = indicator;
                } catch (RuntimeException error) { disconnectClient("awake_unavailable"); return; }
            }
            // Service must keep the screen on while OTHER apps are foreground.
            // Activity FLAG_KEEP_SCREEN_ON alone cannot do that. Bound the legacy
            // screen wake lock to a live authenticated session; no wake-up flag.
            if (awake == null) { awake = power.newWakeLock(android.os.PowerManager.SCREEN_BRIGHT_WAKE_LOCK, "uca:connected"); awake.setReferenceCounted(false); }
            awake.acquire(5000);
        } else {
            if (awakeIndicator != null) {
                try { ((WindowManager)getSystemService(WINDOW_SERVICE)).removeView(awakeIndicator); }
                catch (RuntimeException ignored) {}
                awakeIndicator = null;
            }
            if (awake != null && awake.isHeld()) awake.release();
        }
    }
    void disconnectClient() { disconnectClient("stopped"); }
    private void disconnectClient(String reason) {
        if (client != null) lastDisconnect = reason;
        authenticated = false;
        LocalSocket socket = client; client = null; output = null;
        Runnable cleanup = () -> { removeStrip(); refreshAwake(); };
        if (Looper.myLooper() == Looper.getMainLooper()) cleanup.run(); else main.post(cleanup);
        // shutdown unblocks a reader before close; never wait for socket I/O on
        // the main looper that owns the awake lease and its timeout callbacks.
        if (socket != null) new Thread(() -> {
            try { socket.shutdownInput(); } catch (IOException ignored) {}
            try { socket.shutdownOutput(); } catch (IOException ignored) {}
            try { socket.close(); } catch (IOException ignored) {}
        }, "edge-close").start();
    }
    @Override public void onConfigurationChanged(Configuration config) {
        super.onConfigurationChanged(config);
        // Rotation/folding invalidate geometry: release, then recreate on next handoff.
        if (client != null && strip != null) { send("RETURN", client); removeStrip(); }
    }
    @Override public void onAccessibilityEvent(AccessibilityEvent event) {}
    @Override public void onInterrupt() { disconnectClient(); }
    @Override public void onDestroy() {
        running = false; instance = null; main.removeCallbacks(watchdog); disconnectClient(); removeStrip();
        if (server != null) try { server.close(); } catch (IOException ignored) {}
        writer.shutdownNow(); super.onDestroy();
    }
}
