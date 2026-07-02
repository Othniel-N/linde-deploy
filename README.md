python3 - <<'PY'
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
run("cudaMallocManaged (UVM)", managed=True) # nvbuf-memory-type=3  <-- your current setting
PY
