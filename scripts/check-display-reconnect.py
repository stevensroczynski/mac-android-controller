#!/usr/bin/env python3
"""Opt-in physical Wi-Fi regression: opens/closes the viewer eight times.
Requires one paired, unlocked phone. Does not send video, clicks or keystrokes.
"""
import subprocess,time,shutil,sys
if sys.argv[1:] != ['--run']:
 raise SystemExit('Use --run with one unlocked, paired Wi-Fi phone; this changes its foreground activity.')
adb=shutil.which('adb')
if not adb:raise SystemExit('ADB is required.')
rows=[r.split() for r in subprocess.check_output([adb,'devices'],text=True).splitlines()[1:] if r.strip()]
targets=[r[0] for r in rows if r[1]=='device' and '_adb-tls-connect._tcp' in r[0]]
if len(targets)!=1:raise SystemExit('Exactly one paired Wi-Fi phone is required.')
t=targets[0]
def call(*args):return subprocess.check_output([adb,'-s',t,*args],text=True,stderr=subprocess.DEVNULL,timeout=10)
def status():return call('shell','content','query','--uri','content://org.openinput.uca.pairing/display_status')
assert 'inputRestricted=true' not in call('shell','dumpsys','window','policy'), 'Phone locked'
for i in range(8):
 call('shell','am','start','--activity-clear-top','--activity-single-top','--es','orientation','portrait' if i%2==0 else 'landscape','-n','org.openinput.uca/.DisplayActivity')
 for attempt in range(20):
  if 'phase=listening' in status():break
  time.sleep(.1)
 else:raise AssertionError('Receiver did not reopen: '+status())
 # No client connects: this specifically exercises cancellation of blocked accept.
 call('shell','am','start','-n','org.openinput.uca/.MainActivity')
 time.sleep(.2)
 print('Idle listener reopen',i+1,'passed.',flush=True)
