package org.openinput.uca;

import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.Binder;

/** Bootstrap only through an explicitly authorized ADB shell, never the LAN. */
public final class PairingProvider extends ContentProvider {
    @Override public boolean onCreate() { return true; }
    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        if (Binder.getCallingUid() != 2000) throw new SecurityException("Authorized ADB shell required");
        if ("/status".equals(uri.getPath())) {
            EdgeService service = EdgeService.instance;
            MatrixCursor status = new MatrixCursor(new String[]{"connected", "idle_ms", "awake"});
            status.addRow(new Object[]{service != null && service.connected() ? 1 : 0, service == null ? -1 : service.idleMillis(), service != null && service.awakeHeld() ? 1 : 0});
            return status;
        }
        if (!"/credentials".equals(uri.getPath())) throw new IllegalArgumentException("Unknown path");
        MatrixCursor row = new MatrixCursor(new String[]{"device_id", "token"});
        row.addRow(new Object[]{MainActivity.deviceId(getContext()), MainActivity.token(getContext())});
        return row;
    }
    @Override public String getType(Uri uri) { return "vnd.android.cursor.item/vnd.org.openinput.uca.credentials"; }
    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
