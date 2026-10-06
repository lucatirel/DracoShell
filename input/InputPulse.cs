using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace Draco
{
    // Effects receive anonymous presses only. No key/character/line, console
    // input, clipboard, history, logging, network or global keyboard hook.
    public sealed class PulseGate
    {
        public const int OnMilliseconds = 140;
        public const int GapMilliseconds = 70;
        public const int QueueLimit = 8;
        private int waiting;
        private long changeAt;
        private bool active;
        public void Press() { if (waiting < QueueLimit) waiting++; }
        public bool Pending { get { return active || waiting > 0; } }
        public int Advance(long milliseconds)
        {
            if (milliseconds < changeAt) return -1;
            if (active)
            {
                active = false;
                changeAt = milliseconds + GapMilliseconds;
                return 0;
            }
            if (waiting == 0) return -1;
            waiting--;
            active = true;
            changeAt = milliseconds + OnMilliseconds;
            return 1;
        }
    }

    public static class InputPulse
    {
        // DECCARA changes ONLY the background attribute of one fixed output cell.
        // Characters, foreground, caret, cursor and editor state are untouched.
        // An explicit RGB background survives Terminal's premultiplied shader
        // texture; OSC 11 default backgrounds can have alpha=0 and lose RGB.
        public const string Protocol = "cell-v4-fire";
        public const string OnSequence = "\u001b[1;1;1;1;48;2;5;56;22$r";
        public const string OffSequence = "\u001b[1;1;1;1;49$r";
        public const string DiagnosticSequence = "\u001b[1;1;1;1;48;2;0;176;64$r";
        private static readonly object sync = new object();
        private static readonly Stopwatch clock = Stopwatch.StartNew();
        private static PulseGate gate;
        private static Timer timer;
        private static volatile bool enabled;
        private static volatile bool running;
        private static int clickRequests, wakeQueued, tickBusy;
        private static long requestedFireAt = -1;
        private static readonly WaitCallback wakeWorker = WakeWorker;
        private static IntPtr output;
        private static int transport, outputError;
        private static long received, emitted, fires;
        private static long fireAt = -1;
        private static bool typingActive;
        private static int lastFireStage = -1;
        public const int FireMilliseconds = 900;
        // Tests in the same compiled assembly can observe boolean output events.
        // This seam is internal and never configured by the production profile.
        internal static Action<bool> OutputObserver { get; set; }
        internal static Action<string> SequenceObserver { get; set; }

        [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int kind);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool GetConsoleMode(IntPtr handle, out uint mode);
        [DllImport("kernel32.dll", SetLastError=true)]
        private static extern bool SetConsoleMode(IntPtr handle, uint mode);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true, ExactSpelling=true)]
        private static extern bool WriteConsoleW(IntPtr handle, string fixedSequence,
            uint length, out uint written, IntPtr reserved);

        static InputPulse() { AppDomain.CurrentDomain.ProcessExit += delegate { Stop(); }; }
        public static bool Enabled { get { lock (sync) { return enabled; } } }
        public static long Received { get { return Interlocked.Read(ref received); } }
        public static long Emitted { get { lock (sync) { return emitted; } } }
        public static long Fires { get { return Interlocked.Read(ref fires); } }
        public static int Transport { get { lock (sync) { return transport; } } }
        public static int OutputError { get { lock (sync) { return outputError; } } }
        public static void Start()
        {
            lock (sync)
            {
                if (enabled) return;
                output = GetStdHandle(-11); // Output ONLY, never STD_INPUT_HANDLE.
                uint mode;
                transport = GetConsoleMode(output, out mode) && SetConsoleMode(output, mode | 5u) ? 1 : 2;
                outputError = 0;
                ClearRequests();
                gate = new PulseGate();
                timer = new Timer(Tick, null, Timeout.Infinite, Timeout.Infinite);
                enabled = true;
            }
        }
        // The editor never waits for the output lock or writes to the console.
        // Only bounded anonymous requests cross to the background timer.
        public static void Click()
        {
            if (!enabled) return;
            Interlocked.Increment(ref received);
            int count;
            do
            {
                count = Interlocked.CompareExchange(ref clickRequests, 0, 0);
                if (count >= PulseGate.QueueLimit) break;
            } while (Interlocked.CompareExchange(ref clickRequests, count + 1, count) != count);
            Wake();
        }
        // Repeated Enter replaces one timestamp; never queue delayed flames.
        public static void Fire()
        {
            if (!enabled) return;
            Interlocked.Increment(ref fires);
            Interlocked.Exchange(ref requestedFireAt, clock.ElapsedMilliseconds);
            Wake();
        }
        private static bool RequestsPending()
        {
            return Interlocked.CompareExchange(ref clickRequests, 0, 0) > 0 ||
                Interlocked.Read(ref requestedFireAt) >= 0;
        }
        private static void ClearRequests()
        {
            Interlocked.Exchange(ref clickRequests, 0);
            Interlocked.Exchange(ref requestedFireAt, -1);
        }
        private static void Wake()
        {
            if (running) return;
            if (Interlocked.CompareExchange(ref wakeQueued, 1, 0) == 0)
                ThreadPool.QueueUserWorkItem(wakeWorker);
        }
        private static void WakeWorker(object ignored)
        {
            try
            {
                lock (sync)
                {
                    if (enabled && !running && RequestsPending())
                    {
                        running = true;
                        timer.Change(0, 16); // At most one wake per display frame.
                    }
                }
            }
            finally
            {
                Interlocked.Exchange(ref wakeQueued, 0);
                lock (sync)
                {
                    // Close the worker/idle-stop handoff race without involving
                    // the editor thread in this lock.
                    if (enabled && !running && RequestsPending()) Wake();
                }
            }
        }
        public static int FlameStage(long elapsed)
        {
            return elapsed < 0 || elapsed >= FireMilliseconds ? -1 :
                (int)(elapsed * 20 / FireMilliseconds);
        }
        private static int CurrentFireStage()
        {
            return fireAt < 0 ? -1 : FlameStage(clock.ElapsedMilliseconds - fireAt);
        }
        private static void WriteSignal(bool on)
        {
            typingActive = on;
            int stage = CurrentFireStage();
            lastFireStage = stage;
            if (OutputObserver != null) { OutputObserver(on); return; }
            // Same opaque control cell as the working green-bolt bridge.
            // G encodes activity, B encodes anonymous flame age, no input data.
            if (stage >= 0)
                WriteSequence("\u001b[1;1;1;1;48;2;5;" + (on ? "56" : "8") + ";" + (80 + stage) + "$r");
            else WriteSequence(on ? OnSequence : OffSequence);
        }
        private static void WriteSequence(string sequence)
        {
            if (SequenceObserver != null) { SequenceObserver(sequence); return; }
            if (transport == 1)
            {
                uint written;
                if (WriteConsoleW(output, sequence, (uint)sequence.Length, out written, IntPtr.Zero)
                    && written == sequence.Length) return;
                outputError = Marshal.GetLastWin32Error();
            }
            // Redirected test hosts have no console handle; production uses the
            // native output handle, bypassing a replaced/redirected Console.Out.
            Console.Write(sequence);
        }
        private static void Tick(object ignored)
        {
            // Timer callbacks must not pile up behind a slow output write.
            if (Interlocked.CompareExchange(ref tickBusy, 1, 0) != 0) return;
            try
            {
                lock (sync)
                {
                    if (!enabled || !running) return;
                    int clicks = Interlocked.Exchange(ref clickRequests, 0);
                    for (int i = 0; i < clicks; i++) gate.Press();
                    long requestedFire = Interlocked.Exchange(ref requestedFireAt, -1);
                    if (requestedFire >= 0) fireAt = requestedFire;
                    int signal = gate.Advance(clock.ElapsedMilliseconds);
                    try
                    {
                        if (signal >= 0)
                        {
                            WriteSignal(signal == 1);
                            if (signal == 1) emitted++;
                        }
                        else if (CurrentFireStage() != lastFireStage) WriteSignal(typingActive);
                    }
                    catch { enabled = false; outputError = -1; }
                    if (!enabled || (!gate.Pending && CurrentFireStage() < 0 && !RequestsPending()))
                    {
                        timer.Change(Timeout.Infinite, Timeout.Infinite);
                        running = false;
                        // A request can arrive between the idle check and stopping.
                        if (enabled && RequestsPending()) Wake();
                    }
                }
            }
            finally { Interlocked.Exchange(ref tickBusy, 0); }
        }
        public static void ShowDiagnostic(bool rawBackground)
        {
            lock (sync)
            {
                if (!enabled) return;
                timer.Change(Timeout.Infinite, Timeout.Infinite);
                running = false;
                ClearRequests();
                gate = new PulseGate();
                fireAt = -1;
                if (rawBackground) WriteSequence(DiagnosticSequence);
                else WriteSignal(true);
            }
        }
        public static void Reset()
        {
            lock (sync)
            {
                if (!enabled) return;
                timer.Change(Timeout.Infinite, Timeout.Infinite);
                running = false;
                ClearRequests();
                gate = new PulseGate();
                fireAt = -1;
                Interlocked.Exchange(ref received, 0);
                Interlocked.Exchange(ref fires, 0);
                emitted = 0;
                WriteSignal(false);
            }
        }
        public static void Stop()
        {
            lock (sync)
            {
                if (!enabled && timer == null) return;
                enabled = false;
                ClearRequests();
                running = false;
                fireAt = -1;
                if (timer != null) { timer.Dispose(); timer = null; }
                try { WriteSignal(false); } catch { }
            }
        }
    }
}

