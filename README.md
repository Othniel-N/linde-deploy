root@aks-systempool-28613421-vmss000000:~/LINDE# grep -R "nvurisrcbin\|uridecodebin\|rtspsrc\|streammux\|nvstreammux" .
./app.py:streammux = None
./app.py:def on_source_setup(nvurisrcbin, obj):
./app.py:    if factory_name == "rtspsrc":
./app.py:    def __init__(self, pipeline, streammux, loop):
./app.py:        self.streammux      = streammux
./app.py:        """Create + link source-bin → streammux. Returns True on success."""
./app.py:                    self.streammux.release_request_pad(mux_sinkpad)
./app.py:                    log(f"[src {sid}] released streammux sink_{sid}")
./app.py:        Build source bin (uridecodebin → nvvideoconvert → capsfilter), link
./app.py:        ghost pad to streammux sink_{sid}. Returns None on any failure.
./app.py:        uri_decode_bin = Gst.ElementFactory.make("uridecodebin", f"uri-decode-bin-{idx}")
./app.py:        # memory (type 2) for this GPU-only leg feeding nvstreammux.
./app.py:        sinkpad = self.streammux.get_request_pad(f"sink_{idx}")
./app.py:            log(f"[src {idx}] failed to request streammux sink_{idx}", "ERROR")
./app.py:            log(f"[src {idx}] failed to link source bin → streammux", "ERROR")
./app.py:            self.streammux.release_request_pad(sinkpad)
./app.py:        log(f"[src {idx}] {s['device_id']} — source bin linked → streammux sink_{idx}")
./app.py:    global pipeline, streammux, source_mgr
./app.py:        if "nvstreammux" in src_name or "nvtracker" in src_name:
./app.py:    global ws, ws_lock, facility_id, pipeline, streammux, loop, device_configs, number_sources
./app.py:    streammux = Gst.ElementFactory.make("nvstreammux", "Stream-muxer")
./app.py:    streammux.set_property("width", MUXER_OUTPUT_WIDTH)
./app.py:    streammux.set_property("height", MUXER_OUTPUT_HEIGHT)
./app.py:    streammux.set_property("batch-size", number_sources)
./app.py:    streammux.set_property("batched-push-timeout", 40000)
./app.py:    streammux.set_property("live-source", 1)
./app.py:    streammux.set_property("nvbuf-memory-type", 2)
./app.py:    streammux.set_property("gpu-id", 0)
./app.py:    streammux.set_property("sync-inputs", 0)
./app.py:    streammux.set_property("drop-pipeline-eos", True)
./app.py:    pipeline.add(streammux)
./app.py:    source_mgr = SourceManager(pipeline, streammux, loop)
./app.py:    streammux.link(pgie)
./app_old.py:streammux = None
./app_old.py:def on_source_setup(nvurisrcbin, obj):
./app_old.py:    if factory_name == "rtspsrc":
./app_old.py:def create_source_bin(index, uri, pipeline, streammux):
./app_old.py:    existing_pad = streammux.get_static_pad(f"sink_{index}")
./app_old.py:        streammux.release_request_pad(existing_pad)
./app_old.py:    uri_decode_bin = Gst.ElementFactory.make("uridecodebin", f"uri-decode-bin-{index}")
./app_old.py:    sinkpad = streammux.get_request_pad(f"sink_{index}")
./app_old.py:        streammux.release_request_pad(sinkpad)
./app_old.py:def remove_source_bin(pipeline, streammux, stream_id, src_bin):
./app_old.py:                streammux.release_request_pad(sinkpad)
./app_old.py:    global pipeline, streammux, source_bins
./app_old.py:                remove_source_bin(pipeline, streammux, stream_id, old_bin)
./app_old.py:            new_bin = create_source_bin(stream_id, source_uri, pipeline, streammux)
./app_old.py:    global pipeline, streammux, active_sources
./app_old.py:        if "nvstreammux" in src_name or "nvtracker" in src_name:
./app_old.py:    global ws, ws_lock, facility_id, pipeline, streammux, loop, device_configs, number_sources
./app_old.py:    streammux = Gst.ElementFactory.make("nvstreammux", "Stream-muxer")
./app_old.py:    streammux.set_property("width", MUXER_OUTPUT_WIDTH)
./app_old.py:    streammux.set_property("height", MUXER_OUTPUT_HEIGHT)
./app_old.py:    streammux.set_property("batch-size", number_sources)
./app_old.py:    streammux.set_property("batched-push-timeout", 40000)
./app_old.py:    streammux.set_property("live-source", 1)
./app_old.py:    streammux.set_property("nvbuf-memory-type", 3)
./app_old.py:    streammux.set_property("gpu-id", 0)
./app_old.py:    streammux.set_property("sync-inputs", 0)
./app_old.py:    streammux.set_property("drop-pipeline-eos", True)
./app_old.py:    pipeline.add(streammux)
./app_old.py:            source_bin = create_source_bin(i, uri, pipeline, streammux)
./app_old.py:    streammux.link(pgie)
./old.py:streammux = None
./old.py:def on_source_setup(nvurisrcbin, obj):
./old.py:    if factory_name == "rtspsrc":
./old.py:def create_source_bin(index, uri, pipeline, streammux):
./old.py:    existing_pad = streammux.get_static_pad(f"sink_{index}")
./old.py:        streammux.release_request_pad(existing_pad)
./old.py:    uri_decode_bin = Gst.ElementFactory.make("uridecodebin", f"uri-decode-bin-{index}")
./old.py:    sinkpad = streammux.get_request_pad(f"sink_{index}")
./old.py:        streammux.release_request_pad(sinkpad)
./old.py:def remove_source_bin(pipeline, streammux, stream_id, src_bin):
./old.py:                streammux.release_request_pad(sinkpad)
./old.py:    global pipeline, streammux, source_bins
./old.py:                remove_source_bin(pipeline, streammux, stream_id, old_bin)
./old.py:            new_bin = create_source_bin(stream_id, source_uri, pipeline, streammux)
./old.py:    global pipeline, streammux, active_sources
./old.py:        if "nvstreammux" in src_name or "nvtracker" in src_name:
./old.py:    global ws, ws_lock, facility_id, pipeline, streammux, loop, device_configs, number_sources
./old.py:    streammux = Gst.ElementFactory.make("nvstreammux", "Stream-muxer")
./old.py:    streammux.set_property("width", MUXER_OUTPUT_WIDTH)
./old.py:    streammux.set_property("height", MUXER_OUTPUT_HEIGHT)
./old.py:    streammux.set_property("batch-size", number_sources)
./old.py:    streammux.set_property("batched-push-timeout", 40000)
./old.py:    streammux.set_property("live-source", 1)
./old.py:    streammux.set_property("nvbuf-memory-type", 3)
./old.py:    streammux.set_property("gpu-id", 0)
./old.py:    streammux.set_property("sync-inputs", 0)
./old.py:    streammux.set_property("drop-pipeline-eos", True)
./old.py:    pipeline.add(streammux)
./old.py:            source_bin = create_source_bin(i, uri, pipeline, streammux)
./old.py:    streammux.link(pgie)
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# 
root@aks-systempool-28613421-vmss000000:~/LINDE# grep -R "nvbuf-memory-type" .
./app.py:        nvvidconv.set_property("nvbuf-memory-type", 2)
./app.py:    streammux.set_property("nvbuf-memory-type", 2)
./app.py:        nvvidconv_cam.set_property("nvbuf-memory-type", 1)
