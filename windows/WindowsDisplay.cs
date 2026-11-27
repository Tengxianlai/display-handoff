using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

public static class WindowsDisplay
{
    const int PathSize = 72, ModeSize = 64;
    const uint ActivePaths = 2, Supplied = 0x20, Validate = 0x40, Apply = 0x80;
    static string permanentPath, sharedPath;
    static uint windowsInput, macInput;

    public static void Configure(string permanent, string shared, uint windows, uint mac)
    {
        if (String.IsNullOrEmpty(permanent) || String.IsNullOrEmpty(shared) ||
            String.Equals(permanent, shared, StringComparison.OrdinalIgnoreCase) ||
            windows < 1 || windows > 255 || mac < 1 || mac > 255 || windows == mac)
            throw new ArgumentException("Invalid display paths or DDC input codes.");
        permanentPath = permanent;
        sharedPath = shared;
        windowsInput = windows;
        macInput = mac;
    }

    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out int paths, out int modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref int paths, IntPtr path, ref int modes, IntPtr mode, IntPtr topology);
    [DllImport("user32.dll")] static extern int SetDisplayConfig(int paths, IntPtr path, int modes, IntPtr mode, uint flags);
    [DllImport("user32.dll")] static extern int DisplayConfigGetDeviceInfo(IntPtr request);
    [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc, IntPtr clip, MonitorCallback callback, IntPtr data);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("dxva2.dll")] static extern bool GetNumberOfPhysicalMonitorsFromHMONITOR(IntPtr monitor, out int count);
    [DllImport("dxva2.dll")] static extern bool GetPhysicalMonitorsFromHMONITOR(IntPtr monitor, int count, [Out] PhysicalMonitor[] physical);
    [DllImport("dxva2.dll")] static extern bool DestroyPhysicalMonitors(int count, [In] PhysicalMonitor[] physical);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool GetVCPFeatureAndVCPFeatureReply(IntPtr monitor, byte feature, IntPtr type, out uint value, out uint maximum);
    [DllImport("dxva2.dll", SetLastError = true)] static extern bool SetVCPFeature(IntPtr monitor, byte feature, uint value);

    delegate bool MonitorCallback(IntPtr monitor, IntPtr dc, IntPtr rect, IntPtr data);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct MonitorInfo
    {
        public int Size, MLeft, MTop, MRight, MBottom, WLeft, WTop, WRight, WBottom, Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string Name;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode, Pack = 1)]
    struct PhysicalMonitor
    {
        public IntPtr Handle;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Description;
    }

    sealed class Layout
    {
        public byte[] Paths, Modes;
        public int Count { get { return Paths.Length / PathSize; } }
        public int Permanent { get { return Find(permanentPath); } }
        public int Shared { get { return Find(sharedPath); } }

        public string DevicePath(int index)
        {
            return DeviceInfo(Paths, index * PathSize + 20, 2, 420, 164);
        }

        int Find(string id)
        {
            for (int index = 0; index < Count; index++)
                if (String.Equals(DevicePath(index), id, StringComparison.OrdinalIgnoreCase))
                    return index;
            return -1;
        }

        int SourceOffset(int index)
        {
            var mode = ReadInt(Paths, index * PathSize + 12);
            if (mode < 0 || mode >= Modes.Length / ModeSize || ReadInt(Modes, mode * ModeSize) != 1)
                throw new InvalidOperationException("Missing Windows desktop mode.");
            return mode * ModeSize;
        }

        public bool AtOrigin(int index)
        {
            int offset = SourceOffset(index);
            return ReadInt(Modes, offset + 28) == 0 && ReadInt(Modes, offset + 32) == 0;
        }

        public bool IsDual { get { return Count == 2 && Permanent >= 0 && Shared >= 0 && AtOrigin(Shared) && !AtOrigin(Permanent); } }
        public bool IsWindowsOnly { get { return Count == 1 && Permanent == 0 && AtOrigin(0); } }

        public Layout OnlyWindows()
        {
            int pathOffset = Permanent * PathSize;
            int sourceOffset = SourceOffset(Permanent);
            int target = ReadInt(Paths, pathOffset + 32);
            if (target < 0 || target >= Modes.Length / ModeSize || ReadInt(Modes, target * ModeSize) != 2)
                throw new InvalidOperationException("Missing Windows-only monitor signal mode.");

            byte[] path = new byte[PathSize], modes = new byte[2 * ModeSize];
            Buffer.BlockCopy(Paths, pathOffset, path, 0, PathSize);
            Buffer.BlockCopy(Modes, sourceOffset, modes, 0, ModeSize);
            Buffer.BlockCopy(Modes, target * ModeSize, modes, ModeSize, ModeSize);
            Array.Clear(path, 12, 4);
            Buffer.BlockCopy(BitConverter.GetBytes(1), 0, path, 32, 4);
            Array.Clear(modes, 28, 8);
            return new Layout { Paths = path, Modes = modes };
        }

        public void ApplyLayout()
        {
            var paths = GCHandle.Alloc(Paths, GCHandleType.Pinned);
            var modes = GCHandle.Alloc(Modes, GCHandleType.Pinned);
            try
            {
                Check(SetDisplayConfig(Count, paths.AddrOfPinnedObject(), Modes.Length / ModeSize, modes.AddrOfPinnedObject(), Supplied | Validate), "Validate layout");
                Check(SetDisplayConfig(Count, paths.AddrOfPinnedObject(), Modes.Length / ModeSize, modes.AddrOfPinnedObject(), Supplied | Apply), "Apply layout");
            }
            finally { modes.Free(); paths.Free(); }
        }
    }

    static int ReadInt(byte[] buffer, int offset) { return BitConverter.ToInt32(buffer, offset); }

    static void Check(int result, string operation)
    {
        if (result != 0) throw new InvalidOperationException(operation + " returned " + result);
    }

    static string DeviceInfo(byte[] path, int key, int type, int size, int stringOffset)
    {
        byte[] request = new byte[size];
        Buffer.BlockCopy(BitConverter.GetBytes(type), 0, request, 0, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(size), 0, request, 4, 4);
        Buffer.BlockCopy(path, key, request, 8, 12);
        var pinned = GCHandle.Alloc(request, GCHandleType.Pinned);
        try
        {
            Check(DisplayConfigGetDeviceInfo(pinned.AddrOfPinnedObject()), "Get Windows display information");
            return Encoding.Unicode.GetString(request, stringOffset, size - stringOffset).Split('\0')[0];
        }
        finally { pinned.Free(); }
    }

    static Layout ReadLayout()
    {
        for (int attempt = 0; attempt < 3; attempt++)
        {
            int paths, modes;
            Check(GetDisplayConfigBufferSizes(ActivePaths, out paths, out modes), "Get display buffer sizes");
            byte[] pathData = new byte[paths * PathSize], modeData = new byte[modes * ModeSize];
            var pathPin = GCHandle.Alloc(pathData, GCHandleType.Pinned);
            var modePin = GCHandle.Alloc(modeData, GCHandleType.Pinned);
            int result;
            try { result = QueryDisplayConfig(ActivePaths, ref paths, pathPin.AddrOfPinnedObject(), ref modes, modePin.AddrOfPinnedObject(), IntPtr.Zero); }
            finally { modePin.Free(); pathPin.Free(); }
            if (result == 122) continue;
            Check(result, "Read display layout");
            Array.Resize(ref pathData, paths * PathSize);
            Array.Resize(ref modeData, modes * ModeSize);
            return new Layout { Paths = pathData, Modes = modeData };
        }
        throw new InvalidOperationException("Windows display layout was changing during the query.");
    }

    static void SaveDual(Layout layout, string file)
    {
        File.WriteAllLines(file + ".tmp", new string[] { Convert.ToBase64String(layout.Paths), Convert.ToBase64String(layout.Modes) });
        if (File.Exists(file)) File.Replace(file + ".tmp", file, null);
        else File.Move(file + ".tmp", file);
    }

    public static string Describe()
    {
        var layout = ReadLayout();
        if (layout.IsDual) return "dual";
        if (layout.IsWindowsOnly) return "windows-only";
        return "unexpected";
    }

    public static string[] Discover()
    {
        var layout = ReadLayout();
        if (layout.Count != 2 || layout.AtOrigin(0) == layout.AtOrigin(1))
            throw new InvalidOperationException("Extend Windows across exactly two displays and make the shared display primary.");
        int primary = layout.AtOrigin(0) ? 0 : 1;
        return new string[] { layout.DevicePath(1 - primary), layout.DevicePath(primary) };
    }

    public static void CaptureDual(string file)
    {
        var layout = ReadLayout();
        if (!layout.IsDual) throw new InvalidOperationException("Expected the two configured displays with the shared display primary.");
        SaveDual(layout, file);
    }

    public static void Restore(string file)
    {
        var live = ReadLayout();
        if (live.IsDual) return;
        if (!live.IsWindowsOnly) throw new InvalidOperationException("Unexpected display layout. Restore both displays in Windows Settings.");
        try
        {
            string[] data = File.ReadAllLines(file);
            var saved = new Layout { Paths = Convert.FromBase64String(data[0]), Modes = Convert.FromBase64String(data[1]) };
            if (saved.Paths.Length != 2 * PathSize || saved.Modes.Length < 3 * ModeSize || saved.Modes.Length % ModeSize != 0)
                throw new InvalidOperationException("Invalid saved Windows display layout.");
            saved.ApplyLayout();
        }
        catch (InvalidOperationException)
        {
            Check(SetDisplayConfig(0, IntPtr.Zero, 0, IntPtr.Zero, Apply | 0x0F), "Restore stored Windows display layout");
        }
        Thread.Sleep(1200);
        if (!ReadLayout().IsDual) throw new InvalidOperationException("Windows did not restore the shared monitor as primary.");
    }

    static int WithSharedMonitor(Layout layout, Func<IntPtr, int> operation)
    {
        int shared = layout.Shared;
        if (shared < 0) return -1;
        string source = DeviceInfo(layout.Paths, shared * PathSize, 1, 84, 20);
        int result = -1;
        Exception error = null;
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (monitor, dc, rect, data) =>
        {
            var info = new MonitorInfo { Size = Marshal.SizeOf(typeof(MonitorInfo)) };
            if (!GetMonitorInfo(monitor, ref info) || !string.Equals(source, info.Name, StringComparison.OrdinalIgnoreCase)) return true;
            int count;
            if (!GetNumberOfPhysicalMonitorsFromHMONITOR(monitor, out count) || count != 1) return false;
            var physical = new PhysicalMonitor[count];
            if (!GetPhysicalMonitorsFromHMONITOR(monitor, count, physical)) return false;
            try { result = operation(physical[0].Handle); }
            catch (Exception failure) { error = failure; }
            finally { DestroyPhysicalMonitors(count, physical); }
            return false;
        }, IntPtr.Zero);
        if (error != null) throw error;
        return result;
    }

    static int ReadInput(IntPtr monitor)
    {
        uint value, maximum;
        return GetVCPFeatureAndVCPFeatureReply(monitor, 0x60, IntPtr.Zero, out value, out maximum) ? (int)(value & 0xff) : -1;
    }

    public static int Input() { return WithSharedMonitor(ReadLayout(), ReadInput); }

    static void ApplyWindowsOnly(Layout layout)
    {
        layout.OnlyWindows().ApplyLayout();
        for (int attempt = 0; attempt < 8; attempt++)
        {
            if (ReadLayout().IsWindowsOnly) return;
            Thread.Sleep(150);
        }
        throw new InvalidOperationException("The Windows-only display layout did not verify.");
    }

    public static void AdoptMac(string file)
    {
        var dual = ReadLayout();
        if (dual.IsWindowsOnly) return;
        if (!dual.IsDual || Input() == windowsInput) throw new InvalidOperationException("The current Windows layout or monitor input changed.");
        SaveDual(dual, file);
        try { ApplyWindowsOnly(dual); }
        catch { dual.ApplyLayout(); throw; }
    }

    public static void SelectMac(string file, Func<bool> macHasInput)
    {
        var dual = ReadLayout();
        if (!dual.IsDual) throw new InvalidOperationException("Windows needs its original two-display layout to switch to Mac.");
        SaveDual(dual, file);

        int result = WithSharedMonitor(dual, monitor =>
        {
            if (ReadInput(monitor) != windowsInput) throw new InvalidOperationException("The shared display must show the configured Windows input.");
            if (!SetVCPFeature(monitor, 0x60, macInput)) throw new InvalidOperationException("DDC switch to Mac failed: " + Marshal.GetLastWin32Error());
            bool layoutMayHaveChanged = false;
            try
            {
                if (!macHasInput()) throw new InvalidOperationException("Mac did not confirm the configured input.");
                layoutMayHaveChanged = true;
                ApplyWindowsOnly(dual);
                return 0;
            }
            catch
            {
                // Retain the DDC handle when rolling back a failed handoff.
                if (layoutMayHaveChanged) dual.ApplyLayout();
                SetVCPFeature(monitor, 0x60, windowsInput);
                for (int attempt = 0; attempt < 6; attempt++)
                {
                    if (ReadInput(monitor) == windowsInput) throw;
                    Thread.Sleep(250);
                }
                if (Input() != windowsInput)
                    throw new InvalidOperationException("Could not verify rollback. Use the monitor menu to select the Windows input.");
                throw;
            }
        });
        if (result != 0) throw new InvalidOperationException("The Windows DDC handle for the shared monitor is unavailable.");
    }
}
