ffmpeg -rtsp_transport tcp -i "rtsp://ADMIN:1234@10.81.224.2:554/snl/live/1/1" -t 5 -f null -
ffmpeg version 6.0.1 Copyright (c) 2000-2023 the FFmpeg developers
  built with gcc 9 (Ubuntu 9.4.0-1ubuntu1~20.04.2)
  configuration: --disable-debug --disable-doc --disable-ffplay --enable-fontconfig --enable-gpl --enable-libaom --enable-libaribb24 --enable-libass --enable-libbluray --enable-libfdk_aac --enable-libfreetype --enable-libkvazaar --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb --enable-libopenjpeg --enable-libopus --enable-libsrt --enable-libtheora --enable-libvidstab --enable-libvmaf --enable-libvorbis --enable-libvpx --enable-libwebp --enable-libx264 --enable-libx265 --enable-libxvid --enable-libzimg --enable-libzmq --enable-nonfree --enable-openssl --enable-postproc --enable-shared --enable-small --enable-version3 --extra-cflags=-I/opt/ffmpeg/include --extra-ldflags=-L/opt/ffmpeg/lib --extra-libs=-ldl --extra-libs=-lpthread --prefix=/opt/ffmpeg
  libavutil      58.  2.100 / 58.  2.100
  libavcodec     60.  3.100 / 60.  3.100
  libavformat    60.  3.100 / 60.  3.100
  libavdevice    60.  1.100 / 60.  1.100
  libavfilter     9.  3.100 /  9.  3.100
  libswscale      7.  1.100 /  7.  1.100
  libswresample   4. 10.100 /  4. 10.100
  libpostproc    57.  1.100 / 57.  1.100
Input #0, rtsp, from 'rtsp://ADMIN:1234@10.81.224.2:554/snl/live/1/1':
  Metadata:
    title           : NVT
    comment         : From NVT
  Duration: N/A, start: 0.000375, bitrate: N/A
  Stream #0:0: Video: hevc, yuv420p(tv), 2880x1620, 15 fps, 25 tbr, 90k tbn
  Stream #0:1: Audio: pcm_alaw, 8000 Hz, mono, s16, 64 kb/s
  Stream #0:2: Data: none
Stream mapping:
  Stream #0:0 -> #0:0 (hevc (native) -> wrapped_avframe (native))
  Stream #0:1 -> #0:1 (pcm_alaw (native) -> pcm_s16le (native))
Press [q] to stop, [?] for help
Output #0, null, to 'pipe:':
  Metadata:
    title           : NVT
    comment         : From NVT
    encoder         : Lavf60.3.100
  Stream #0:0: Video: wrapped_avframe, yuv420p(tv, progressive), 2880x1620, q=2-31, 200 kb/s, 25 fps, 25 tbn
    Metadata:
      encoder         : Lavc60.3.100 wrapped_avframe
  Stream #0:1: Audio: pcm_s16le, 8000 Hz, mono, s16, 128 kb/s
    Metadata:
      encoder         : Lavc60.3.100 pcm_s16le
frame=   74 fps= 19 q=-0.0 Lsize=N/A time=00:00:04.92 bitrate=N/A speed=1.23x     speed=12.4x    
video:35kB audio:78kB subtitle:0kB other streams:0kB global headers:0kB muxing overhead: unknown
root@ffmpeg-test:/tmp/workdir# 
