# mini-linux

## Automatically run a command

```
qemu-system-x86_64 -smbios type=11,value="eval:cat /proc/cpuinfo"
qemu-system-x86_64 -smbios type=11,value="loop:date; sleep 1"

# If no space character is possible:
qemu-system-x86_64 -smbios 'type=11,value=eval:cmd=cat_/proc/cpuinfo;IFS=_;$cmd'
# or: type=11,value=eval:cmd=$'cat\x20/proc/cpuinfo';$cmd
```
