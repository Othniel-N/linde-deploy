 kubectl exec -it linde-ppe-7df68db678-rd7kb -n linde -- bash
root@aks-systempool-28613421-vmss000000:~/LINDE# ls
Dockerfile       app.py      device_config.json  facility_config.json        models  pgie_config.txt   requirements.txt  tracker_config.yml
Dockerfile.data  app_old.py  docker-compose.yml  model_b32_gpu0_fp16.engine  old.py  registeration.py  sgie_config.txt
root@aks-systempool-28613421-vmss000000:~/LINDE# nano facility_config.json 
root@aks-systempool-28613421-vmss000000:~/LINDE# cat facility_config.json 
{"success":true,"message":"Device configuration updated successfully","device":{"id":1,"hostname":"aks-systempool-28613421-vmss00000K","macAddress":"66:88:e5:30:44:44","configuration":"CPU: AMD EPYC 74F3 24-Core Processor, RAM: 53Gi, OS: Ubuntu 24.04.1 LTS, Manufacturer: Microsoft Corporation Virtual Machine, Firmware: Hyper-V UEFI Release v4.1","ipAddress":"10.151.136.5","status":"active","facilityId":2,"zippedFilesPath":"/api/download-zip?hostname=aks-systempool-28613421-vmss00000K&macAddress=66%3A88%3Ae5%3A30%3A44%3A44","facility":{"id":2,"name":"LINDE INDIA PRIVATE LIMITED","brand":"LINDE"},"devices":[{"id":2,"name":"Camera channel 1","ip":"10.81.224.2","username":"ADMIN","password":"1234","rtsp_link":"rtsp://ADMIN:1234@10.81.224.2:554/snl/live/1/1","edge_devices_found":null,"polygon":null,"x":0,"y":0,"zoneId":2,"protocols":[],"enabledUseCases":["safety_compliance"]}],"visualizerConfigs":[]}}root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# ls
Dockerfile       app.py      device_config.json  facility_config.json        models  pgie_config.txt   requirements.txt  tracker_config.yml
Dockerfile.data  app_old.py  docker-compose.yml  model_b32_gpu0_fp16.engine  old.py  registeration.py  sgie_config.txt
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# ls -l /dev/nvidia-uvm*
crw-rw-rw- 1 root root 509, 0 Dec  3  2025 /dev/nvidia-uvm
crw-rw-rw- 1 root root 509, 1 Dec  3  2025 /dev/nvidia-uvm-tools
root@aks-systempool-28613421-vmss000000:~/LINDE# grep -i uvm /proc/modules
nvidia_uvm 4673536 2 - Live 0x0000000000000000 (POE)
nvidia 54300672 67 nvidia_modeset,nvidia_uvm, Live 0x0000000000000000 (POE)
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# python3 - <<'PY'
import ctypes, sys
lib = None
for name in ("libcudart.so", "libcudart.so.12", "libcudart.so.11.0"):
    try:
        lib = ctypes.CDLL(name); break
    except OSError:
        continue
if lib is None:
    sys.exit("Could not load libcudart.so")
 
lib.cudaGetErrorString.restype = ctypes.c_char_p
SIZE = 4 * 1024 * 1024   # 4 MiB
 
def run(label, managed):
    ptr = ctypes.c_void_p()
    if managed:
        ret = lib.cudaMallocManaged(ctypes.byref(ptr), ctypes.c_size_t(SIZE), ctypes.c_uint(1))
    else:
        ret = lib.cudaMalloc(ctypes.byref(ptr), ctypes.c_size_t(SIZE))
    msg = lib.cudaGetErrorString(ret).decode()
    print(f"{label:22s} ret={ret}  ({msg})")
    if ret == 0:
        lib.cudaFree(ptr)
 
run("cudaMalloc (device)",  managed=False)   # nvbuf-memory-type=2
PYn("cudaMallocManaged (UVM)", managed=True) # nvbuf-memory-type=3  <-- your current setting
cudaMalloc (device)    ret=0  (no error)
cudaMallocManaged (UVM) ret=801  (operation not supported)
root@aks-systempool-28613421-vmss000000:~/LINDE# 
