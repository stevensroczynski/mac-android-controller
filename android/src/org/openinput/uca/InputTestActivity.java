package org.openinput.uca;

import android.app.Activity;
import android.os.Bundle;
import android.view.*;
import android.widget.TextView;

/** Isolated, deliberately opened test surface. Counts only events delivered to this activity. */
public final class InputTestActivity extends Activity {
    private int hover, clicks, scroll, keysDown, keysUp;
    private TextView label;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        label = new TextView(this); label.setTextSize(24); label.setPadding(30,80,30,30);
        label.setFocusableInTouchMode(true); setContentView(label); label.requestFocus(); update();
    }
    private void update() { label.setText("USB input test\n\nHover: " + hover + "\nClicks: " + clicks + "\nScroll: " + scroll + "\nKey down: " + keysDown + "\nKey up: " + keysUp + "\n\nNo typed characters are retained. Close this screen after testing."); }
    @Override public boolean dispatchGenericMotionEvent(MotionEvent e) {
        if (e.getActionMasked() == MotionEvent.ACTION_HOVER_MOVE) hover++;
        if (e.getActionMasked() == MotionEvent.ACTION_SCROLL) scroll++;
        update(); return true;
    }
    @Override public boolean dispatchTouchEvent(MotionEvent e) {
        if (e.getActionMasked() == MotionEvent.ACTION_DOWN) clicks++;
        update(); return true;
    }
    @Override public boolean dispatchKeyEvent(KeyEvent e) {
        if (e.getKeyCode() == KeyEvent.KEYCODE_BACK) return super.dispatchKeyEvent(e);
        if (e.getAction() == KeyEvent.ACTION_DOWN) keysDown++;
        if (e.getAction() == KeyEvent.ACTION_UP) keysUp++;
        update(); return true;
    }
}
