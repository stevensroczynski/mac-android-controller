package org.openinput.bridge;

import android.system.Os;
import android.system.OsConstants;
import android.system.StructPollfd;
import java.io.*;
import java.nio.*;
import java.nio.charset.StandardCharsets;

/** Authorized adb-shell helper. Uses public android.system APIs and the Linux UHID UAPI. */
public final class HIDBridge {
    private static FileDescriptor keyboard, mouse;
    private static byte[] read(int length) throws Exception {
        byte[] bytes = new byte[length]; int offset = 0;
        while (offset < length) {
            StructPollfd poll = new StructPollfd(); poll.fd = FileDescriptor.in; poll.events = (short)OsConstants.POLLIN;
            if (Os.poll(new StructPollfd[]{poll}, 3000) <= 0) throw new IOException("Host heartbeat expired");
            int n = Os.read(FileDescriptor.in, bytes, offset, length-offset);
            if (n <= 0) throw new EOFException(); offset += n;
        }
        return bytes;
    }
    private static FileDescriptor create(String name, byte[] descriptor) throws Exception {
        FileDescriptor fd = Os.open("/dev/uhid", OsConstants.O_RDWR | OsConstants.O_CLOEXEC, 0);
        try {
            ByteBuffer b = ByteBuffer.allocate(280+descriptor.length).order(ByteOrder.nativeOrder());
            b.putInt(11); // UHID_CREATE2
            b.put(name.getBytes(StandardCharsets.US_ASCII)); b.position(260);
            b.putShort((short)descriptor.length); b.putShort((short)6); // BUS_VIRTUAL
            b.putInt(0); b.putInt(0); b.putInt(1); b.putInt(0); b.put(descriptor);
            write(fd,b.array());
            // Consume kernel events, answer feature queries without retaining input.
            Thread reader = new Thread(() -> {
                byte[] event = new byte[4380];
                try { while (true) {
                    int n = Os.read(fd,event,0,event.length); if(n<4) break;
                    ByteBuffer e = ByteBuffer.wrap(event).order(ByteOrder.nativeOrder()); int type=e.getInt();
                    if ((type==9 || type==13) && n>=8) {
                        ByteBuffer reply=ByteBuffer.allocate(type==9 ? 12 : 10).order(ByteOrder.nativeOrder());
                        reply.putInt(type==9 ? 10 : 14); reply.putInt(e.getInt()); reply.putShort((short)OsConstants.EIO);
                        write(fd,reply.array());
                    }
                }} catch(Exception ignored) {}
            }, "uhid-kernel"); reader.setDaemon(true); reader.start();
            return fd;
        } catch(Exception e) { Os.close(fd); throw e; }
    }
    private static void write(FileDescriptor fd,byte[] bytes) throws Exception {
        if(Os.write(fd,bytes,0,bytes.length)!=bytes.length) throw new IOException("Short UHID write");
    }
    private static void input(FileDescriptor fd,byte[] report) throws Exception {
        ByteBuffer b=ByteBuffer.allocate(6+report.length).order(ByteOrder.nativeOrder());
        b.putInt(12); b.putShort((short)report.length); b.put(report); write(fd,b.array());
    }
    private static byte[] descriptor() throws Exception {
        byte[] len=read(2); int size=((len[0]&255)<<8)|(len[1]&255);
        if(size<1 || size>256) throw new IOException("Descriptor size"); return read(size);
    }
    private static void close(FileDescriptor fd) { if(fd!=null) try { Os.close(fd); } catch(Exception ignored) {} }
    public static void main(String[] args) {
        try {
            if(!java.util.Arrays.equals(read(4),new byte[]{85,67,65,49})) return;
            keyboard=create("UCA Keyboard",descriptor()); mouse=create("UCA Mouse",descriptor());
            System.out.write(new byte[]{85,67,65,49}); System.out.flush();
            while(true) {
                int id=read(1)[0]&255;
                if(id==1) input(keyboard,read(8));
                else if(id==2) input(mouse,read(5));
                else if(id==3) { input(keyboard,new byte[8]); input(mouse,new byte[5]); }
                else if(id!=0) break;
                System.out.write(0); System.out.flush();
            }
        } catch(Exception ignored) { /* Deliberately no typed input, secrets, or device identifiers in logs. */ }
        finally { close(mouse); close(keyboard); }
        // Closing UHID destroys devices even after host crash, EOF, or watchdog expiry.
        System.exit(0);
    }
}
