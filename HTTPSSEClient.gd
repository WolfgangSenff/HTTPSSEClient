extends Node

signal new_sse_event(headers, event, data)
signal connected

const event_tag = "event:"
const data_tag = "data:"

var httpclient = HTTPClient.new()
var is_connected = false

func connect_to_host(domain : String, url_after_domain : String, port : int = -1, use_ssl : bool = false, verify_host : bool = true):
    var err = 0
    err = httpclient.connect_to_host(domain, port, use_ssl, verify_host)

    while(httpclient.get_status() == HTTPClient.STATUS_CONNECTING or httpclient.get_status() == HTTPClient.STATUS_RESOLVING):
        httpclient.poll()
        var tree = get_tree()
        if tree:
            yield(get_tree().create_timer(0.1), "timeout")

    err = httpclient.request(HTTPClient.METHOD_POST, url_after_domain, ["Accept: text/event-stream"])
    if err == OK:
        emit_signal("connected")
        is_connected = true

func _process(delta):
    if !is_connected:
        return

    while (httpclient.get_status() == HTTPClient.STATUS_REQUESTING):
        httpclient.poll()
        yield(get_tree().create_timer(0.1), "timeout")

    var response_body = PoolByteArray()

    if(httpclient.has_response()):
        var headers = httpclient.get_response_headers_as_dictionary()

        while(httpclient.get_status() == HTTPClient.STATUS_BODY):
            httpclient.poll()
            var chunk = httpclient.read_response_body_chunk()
            if(chunk.size() == 0):
                yield(get_tree().create_timer(0.1), "timeout")
            else:
                response_body = response_body + chunk

            var body = response_body.get_string_from_utf8()
            if response_body.size() > 0:
                response_body.resize(0)
                var event_data = get_event_data(body)
                emit_signal("new_sse_event", headers, event_data.event, event_data.data)

func get_event_data(body : String) -> Dictionary:
    var result = {}
    var event_idx = body.find(event_tag)
    assert(event_idx != -1)
    var data_idx = body.find(data_tag, event_idx + event_tag.length())
    assert(data_idx != -1)
    var event = body.substr(event_idx, data_idx)
    event = event.replace(event_tag, "").strip_edges()
    assert(event)
    assert(event.length() > 0)
    result["event"] = event
    var data = body.right(data_idx + data_tag.length()).strip_edges()
    assert(data)
    assert(data.length() > 0)
    result["data"] = data
    return result

func _exit_tree():
    if httpclient:
        httpclient.close()

func _notification(what):
    if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
        if httpclient:
            httpclient.close()
        get_tree().quit()