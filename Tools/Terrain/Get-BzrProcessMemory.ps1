# Read-only Windows process/32-bit address-space measurements for local trials.
# Dot-source, then Get-BzrProcessMemory -ProcessId <the harness-owned PID>.
if(-not ('BzrMemory.Snapshot' -as [type])) {
 Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace BzrMemory {
 public class Snapshot {
  [StructLayout(LayoutKind.Sequential)] struct Counters {
   public uint cb, faults;
   public UIntPtr peakWorking, working, peakPagedPool, pagedPool, peakNonPagedPool, nonPagedPool;
   public UIntPtr commit, peakCommit, privateUsage;
  }
  [StructLayout(LayoutKind.Sequential)] struct Region {
   public IntPtr start, allocation;
   public uint allocationProtect;
   public ushort partitionId;
   public UIntPtr size;
   public uint state, protect, type;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", SetLastError=true)] static extern UIntPtr VirtualQueryEx(IntPtr process, IntPtr address, out Region region, UIntPtr length);
  [DllImport("psapi.dll", SetLastError=true)] static extern bool GetProcessMemoryInfo(IntPtr process, ref Counters counters, uint length);
  public ulong privateBytes, peakPrivateBytes, workingSetBytes, peakWorkingSetBytes;
  public ulong vaCommittedBytes, vaReservedBytes, vaFreeBytes, vaLargestFreeBytes;
  public ulong vaPrivateCommittedBytes, vaMappedCommittedBytes, vaImageCommittedBytes, vaScannedThrough;
  public static Snapshot Read(int pid, ulong limit) {
   if(IntPtr.Size != 8) throw new InvalidOperationException("Use 64-bit Windows PowerShell to inspect the full 32-bit address space.");
   IntPtr handle=OpenProcess(0x410, false, pid);
   if(handle==IntPtr.Zero) throw new Win32Exception();
   try {
    var counters=new Counters(); counters.cb=(uint)Marshal.SizeOf(typeof(Counters));
    if(!GetProcessMemoryInfo(handle, ref counters, counters.cb)) throw new Win32Exception();
    var result=new Snapshot { privateBytes=counters.privateUsage.ToUInt64(), peakPrivateBytes=counters.peakCommit.ToUInt64(),
     workingSetBytes=counters.working.ToUInt64(), peakWorkingSetBytes=counters.peakWorking.ToUInt64() };
    ulong address=65536; // Windows' lower allocation guard is not usable headroom.
    while(address < limit) {
     Region region;
     if(VirtualQueryEx(handle, new IntPtr((long)address), out region, (UIntPtr)Marshal.SizeOf(typeof(Region)))==UIntPtr.Zero)
      throw new Win32Exception(Marshal.GetLastWin32Error(), "VirtualQueryEx failed before the target address limit");
     ulong end=Math.Min(limit, (ulong)region.start.ToInt64()+region.size.ToUInt64());
     if(end<=address) throw new InvalidOperationException("VirtualQueryEx did not advance");
     ulong bytes=end-address;
     if(region.state==0x10000) {result.vaFreeBytes+=bytes; result.vaLargestFreeBytes=Math.Max(result.vaLargestFreeBytes, bytes);}
     else if(region.state==0x2000) result.vaReservedBytes+=bytes;
     else if(region.state==0x1000) {
      result.vaCommittedBytes+=bytes;
      if(region.type==0x20000) result.vaPrivateCommittedBytes+=bytes;
      else if(region.type==0x40000) result.vaMappedCommittedBytes+=bytes;
      else if(region.type==0x1000000) result.vaImageCommittedBytes+=bytes;
     }
     else throw new InvalidOperationException("Unknown virtual-memory state");
     address=end;
    }
    result.vaScannedThrough=address; return result;
   } finally {CloseHandle(handle);}
  }
 }
}
'@
}
function Get-BzrProcessMemory([int]$ProcessId) {
 $process=Get-Process -Id $ProcessId -ErrorAction Stop
 $image=$process.MainModule.FileName
 # PE file characteristics, not an assumed 2/4 GiB budget or a patched binary.
 $reader=New-Object IO.BinaryReader([IO.File]::OpenRead($image))
 try {
  if($reader.ReadUInt16() -ne 0x5a4d){throw 'Not a PE image'}
  $reader.BaseStream.Position=0x3c; $pe=$reader.ReadUInt32()
  $reader.BaseStream.Position=$pe
  if($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x14c){throw 'Expected an x86 PE image'}
  $reader.BaseStream.Position=$pe+22
  $largeAddressAware=($reader.ReadUInt16() -band 0x20) -ne 0
 } finally {$reader.Dispose()}
 if(-not [Environment]::Is64BitOperatingSystem){throw 'This probe currently qualifies 32-bit games on 64-bit Windows only'}
 $limit=if($largeAddressAware){[uint64]4294901760}else{[uint64]2147418112}
 $snapshot=[BzrMemory.Snapshot]::Read($ProcessId,$limit)
 $row=[ordered]@{image=$image;largeAddressAware=$largeAddressAware;vaLimitBytes=$limit;virtualBytes=$process.VirtualMemorySize64;peakVirtualBytes=$process.PeakVirtualMemorySize64}
 foreach($field in $snapshot.GetType().GetFields()){$row[$field.Name]=$field.GetValue($snapshot)}
 [pscustomobject]$row
}
