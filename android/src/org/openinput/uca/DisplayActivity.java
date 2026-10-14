package org.openinput.uca;

import android.app.Activity;
import android.os.Bundle;
import android.os.SystemClock;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.media.MediaCodec;
import android.media.MediaFormat;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Receives only an authenticated ADB-forwarded H.264 stream. No LAN listener. */
public final class DisplayActivity extends Activity implements SurfaceHolder.Callback {
    static volatile DisplayActivity instance;
    volatile int received, rendered;
    volatile boolean connected;
    volatile String phase="created";
    volatile String lifecycle="";
    private synchronized void trace(String event) { lifecycle=(lifecycle+" "+event);if(lifecycle.length()>400)lifecycle=lifecycle.substring(lifecycle.length()-400); }
    private volatile boolean active;
    private volatile long generation;
    private volatile LocalServerSocket server;
    private volatile LocalSocket client;
    private SurfaceView surface;
    private View blank;
    private TextView status;
    private FrameLayout root;
    private boolean started, surfaceReady;
    private int videoWidth=1280, videoHeight=800;
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved); instance=this;trace("create");
        applyOrientation(getIntent());
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE | WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        WindowManager.LayoutParams windowParams=getWindow().getAttributes();
        windowParams.layoutInDisplayCutoutMode=WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
        getWindow().setAttributes(windowParams);
        root=new FrameLayout(this); root.setBackgroundColor(0xff000000);
        surface=new SurfaceView(this); surface.getHolder().addCallback(this);
        root.addView(surface, new FrameLayout.LayoutParams(-1,-1,Gravity.CENTER));
        blank=new View(this);blank.setBackgroundColor(0xff000000);root.addView(blank,new FrameLayout.LayoutParams(-1,-1));
        status=new TextView(this); status.setTextColor(0xffffffff); status.setPadding(20,12,20,12); status.setBackgroundColor(0x99000000);
        status.setText("Waiting for your Mac…"); root.addView(status,new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.LEFT));
        root.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob) -> fitVideo());
        setContentView(root);
    }
    private void applyOrientation(android.content.Intent intent) {
        String orientation=intent.getStringExtra("orientation");
        if("portrait".equals(orientation))setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT);
        else if("landscape".equals(orientation))setRequestedOrientation(android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE);
    }
    private void fitVideo() {
        int w=root.getWidth(),h=root.getHeight(); if(w<1 || h<1) return;
        float scale=Math.min((float)w/videoWidth,(float)h/videoHeight);
        int vw=Math.max(1,Math.round(videoWidth*scale)),vh=Math.max(1,Math.round(videoHeight*scale));
        FrameLayout.LayoutParams p=(FrameLayout.LayoutParams)surface.getLayoutParams();
        if(p.width!=vw || p.height!=vh) { p.width=vw;p.height=vh;p.gravity=Gravity.CENTER;surface.setLayoutParams(p); }
    }
    @Override protected void onNewIntent(android.content.Intent intent) {
        super.onNewIntent(intent);setIntent(intent);trace("intent");
        // Opening the companion's viewer must preserve an existing session.
        // The Mac supplies orientation when explicitly starting a new session.
        if(connected && !intent.hasExtra("orientation"))return;
        applyOrientation(intent);stopReceiver();
        status.setText("Waiting for your Mac…");status.setVisibility(View.VISIBLE);
        blank.setVisibility(View.VISIBLE);getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);startReceiver();
    }
    @Override protected void onStart() { super.onStart();started=true;startReceiver(); }
    @Override protected void onResume() {
        super.onResume();trace("resume");
        if(!connected)blank.setVisibility(View.VISIBLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        updatePictureInPicture();startReceiver();
    }
    @Override protected void onPause() {
        trace("pause");
        android.app.KeyguardManager keyguard=(android.app.KeyguardManager)getSystemService(KEYGUARD_SERVICE);
        if(keyguard.isKeyguardLocked()) {blank.setVisibility(View.VISIBLE);stopReceiver();}
        super.onPause();
    }
    @Override protected void onStop() {
        started=false;blank.setVisibility(View.VISIBLE);stopReceiver();super.onStop();
    }
    private boolean supportsPictureInPicture() {
        return getPackageManager().hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE);
    }
    private android.app.PictureInPictureParams pictureInPictureParams() {
        android.app.PictureInPictureParams.Builder builder=new android.app.PictureInPictureParams.Builder()
            .setAspectRatio(new android.util.Rational(Math.round(Math.max(1f/2.39f,Math.min(2.39f,(float)videoWidth/videoHeight))*10000),10000));
        android.graphics.Rect rect=new android.graphics.Rect();
        if(surface.getGlobalVisibleRect(rect))builder.setSourceRectHint(rect);
        if(android.os.Build.VERSION.SDK_INT>=31)builder.setAutoEnterEnabled(connected);
        return builder.build();
    }
    private void updatePictureInPicture() {
        if(supportsPictureInPicture())setPictureInPictureParams(pictureInPictureParams());
    }
    @Override protected void onUserLeaveHint() {
        super.onUserLeaveHint();
        if(android.os.Build.VERSION.SDK_INT<31 && connected && supportsPictureInPicture())
            enterPictureInPictureMode(pictureInPictureParams());
    }
    @Override public void onBackPressed() {
        if(connected && supportsPictureInPicture() && enterPictureInPictureMode(pictureInPictureParams()))return;
        super.onBackPressed();
    }
    @Override public void onPictureInPictureModeChanged(boolean pip,android.content.res.Configuration configuration) {
        super.onPictureInPictureModeChanged(pip,configuration);trace(pip ? "pip_enter" : "pip_exit");
        fitVideo();
    }
    @Override protected void onDestroy() { trace("destroy");stopReceiver();if(instance==this)instance=null;super.onDestroy(); }
    @Override public void surfaceCreated(SurfaceHolder holder) { trace("surface_created");surfaceReady=true;startReceiver(); }
    @Override public void surfaceChanged(SurfaceHolder holder,int format,int w,int h) {}
    @Override public void surfaceDestroyed(SurfaceHolder holder) { trace("surface_destroyed");phase="surface_closed";surfaceReady=false;stopReceiver(); }
    private synchronized void startReceiver() {
        if(!started || !surfaceReady || active) return;
        trace("receiver_start");active=true;phase="starting";
        long session=++generation;
        new Thread(() -> receive(session),"extended-display").start();
    }
    private synchronized void stopReceiver() {
        trace("receiver_stop");generation++;active=false; connected=false;phase="stopped";updatePictureInPicture();
        LocalSocket socket=client; client=null;
        LocalServerSocket listener=server;server=null;
        // shutdown() wakes a blocked accept(); close() alone can leave the old
        // listener holding the abstract address until another client arrives.
        new Thread(() -> {
            closeListener(listener);
            closeClient(socket);
        },"display-close").start();
    }
    private static void closeListener(LocalServerSocket listener) {
        if(listener==null)return;
        synchronized(listener) {
            try {android.system.Os.shutdown(listener.getFileDescriptor(),android.system.OsConstants.SHUT_RDWR);}
            catch(android.system.ErrnoException ignored) {}
            try {listener.close();}catch(IOException ignored){}
        }
    }
    private static void closeClient(LocalSocket socket) {
        if(socket==null)return;
        synchronized(socket) {
            try{socket.shutdownInput();}catch(IOException ignored){}
            try{socket.shutdownOutput();}catch(IOException ignored){}
            try{socket.close();}catch(IOException ignored){}
        }
    }
    private static String line(InputStream in) throws IOException {
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();
        for(int i=0;i<64;i++) { int c=in.read();if(c==10)return bytes.toString("UTF-8");if(c<32||c>126)throw new IOException();bytes.write(c); }
        throw new IOException();
    }
    private boolean alive(long session) { return active && generation==session; }
    private void receive(long session) {
        LocalServerSocket listener=null;
        try {
            // A quick pause/resume may overlap the previous socket's close.
            for(int attempt=0;attempt<10 && alive(session);attempt++) {
                try {listener=new LocalServerSocket("uca-display-v1");break;}
                catch(IOException error) {if(attempt==9)throw error;Thread.sleep(100);}
            }
            synchronized(this) {
                if(listener==null||!alive(session))return;
                server=listener;phase="listening";trace("listening");
            }
            while(alive(session)) {
                LocalSocket socket=listener.accept();
                synchronized(this) {
                    if(!alive(session)){closeClient(socket);break;}
                    client=socket;
                }
                socket.setSoTimeout(5000);
                try {
                    phase="auth";trace("auth");
                    DataInputStream in=new DataInputStream(new BufferedInputStream(socket.getInputStream()));
                    OutputStream out=socket.getOutputStream();
                    String expected="AUTH "+MainActivity.token(this);
                    if(!MessageDigest.isEqual(expected.getBytes(StandardCharsets.US_ASCII),line(in).getBytes(StandardCharsets.US_ASCII))) continue;
                    out.write("OK\n".getBytes(StandardCharsets.US_ASCII));out.flush();
                    phase="header";trace("header");
                    if(in.readInt()!=0x55434431)throw new IOException(); // UCD1
                    int width=in.readUnsignedShort(),height=in.readUnsignedShort();
                    if(width<640||width>2560||height<480||height>2560)throw new IOException();
                    videoWidth=width;videoHeight=height;runOnUiThread(this::fitVideo);
                    phase="decode";
                    decode(session,socket,in,out,width,height);
                } finally {
                    synchronized(this) {if(generation==session)connected=false;if(client==socket)client=null;}
                    closeClient(socket);
                }
            }
        } catch(Exception ignored) {
            if(alive(session)){phase="failed_"+phase+"_"+ignored.getClass().getSimpleName();trace(phase);}
            if(alive(session))runOnUiThread(() -> {if(generation!=session)return;blank.setVisibility(View.VISIBLE);status.setText("Display disconnected. Reconnect from your Mac.");status.setVisibility(View.VISIBLE);getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);updatePictureInPicture();});
        } finally {
            synchronized(this) {
                if(generation==session){connected=false;active=false;}
                if(server==listener)server=null;
            }
            closeListener(listener);
        }
    }
    private void decode(long session,LocalSocket socket,DataInputStream in,OutputStream out,int width,int height) throws Exception {
        // Some phones expose a separate low-latency codec; createDecoderByType
        // may pick a decoder which ignores KEY_LOW_LATENCY.
        MediaFormat requested=MediaFormat.createVideoFormat("video/avc",width,height);
        String decoder=null;
        if(android.os.Build.VERSION.SDK_INT>=30) {
            requested.setFeatureEnabled(android.media.MediaCodecInfo.CodecCapabilities.FEATURE_LowLatency,true);
            decoder=new android.media.MediaCodecList(android.media.MediaCodecList.ALL_CODECS).findDecoderForFormat(requested);
        }
        MediaCodec codec=decoder==null ? MediaCodec.createDecoderByType("video/avc") : MediaCodec.createByCodecName(decoder);
        Thread drain=null;
        final Object renderSignal=new Object();
        final java.util.concurrent.atomic.AtomicBoolean decoding=new java.util.concurrent.atomic.AtomicBoolean(true);
        try {
            MediaFormat format=MediaFormat.createVideoFormat("video/avc",width,height);
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE,4*1024*1024);
            format.setInteger(MediaFormat.KEY_PRIORITY,0);
            if(android.os.Build.VERSION.SDK_INT>=30)format.setInteger(MediaFormat.KEY_LOW_LATENCY,1);
            codec.configure(format,surface.getHolder().getSurface(),null,0);codec.start();
            if(!alive(session))throw new IOException();
            phase="streaming";connected=true;received=0;rendered=0;
            runOnUiThread(() -> {if(generation!=session)return;status.setText("Mac extended display");updatePictureInPicture();getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);});
            drain=new Thread(() -> {
                MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();
                try {while(decoding.get()) {
                    int index=codec.dequeueOutputBuffer(info,10000);
                    if(index>=0) {codec.releaseOutputBuffer(index,true);synchronized(renderSignal){rendered++;renderSignal.notifyAll();}if(rendered==1)runOnUiThread(() -> {if(generation==session){status.setVisibility(View.GONE);blank.setVisibility(View.GONE);}});}
                }}catch(RuntimeException error){decoding.set(false);try{socket.shutdownInput();}catch(IOException ignored){}}
            },"display-render");drain.start();
            while(alive(session) && decoding.get()) {
                int length=in.readInt();long pts=in.readLong();
                if(length<0||length>4*1024*1024||pts<0)throw new IOException();
                if(length>0) {
                    byte[] frame=new byte[length];in.readFully(frame);
                    int index=-1;long deadline=SystemClock.elapsedRealtime()+2000;
                    while(index<0&&alive(session)&&decoding.get()&&SystemClock.elapsedRealtime()<deadline) index=codec.dequeueInputBuffer(10000);
                    if(index<0)throw new IOException();
                    ByteBuffer buffer=codec.getInputBuffer(index);if(buffer==null||buffer.capacity()<length)throw new IOException();
                    buffer.clear();buffer.put(frame);codec.queueInputBuffer(index,0,length,pts,0);received++;
                    // Decoders may need several input frames before their first output.
                    // Bound outstanding work, but never wait for output after frame one.
                    // The low-latency decoder normally drains well below this ceiling.
                    long renderDeadline=SystemClock.elapsedRealtime()+2000;
                    synchronized(renderSignal) {
                        while(received-rendered>=8 && alive(session) && decoding.get()) {
                            long remaining=renderDeadline-SystemClock.elapsedRealtime();
                            if(remaining<=0)throw new IOException("Decoder output timed out");
                            renderSignal.wait(Math.min(remaining,50));
                        }
                    }
                    if(!alive(session)||!decoding.get())throw new IOException();
                }
                out.write(0);out.flush();
            }
        } finally {
            decoding.set(false);if(drain!=null)drain.join(500);
            try{codec.stop();}catch(RuntimeException ignored){}codec.release();
        }
    }
}
