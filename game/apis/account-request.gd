extends RefCounted

const DEFAULT_ROOT := "http://127.0.0.1:8765/api/"
var username: String
var password: String


func _init(name_value: String, password_value: String) -> void:
	username = name_value
	password = password_value


func send(owner: Node) -> Dictionary:
	var request := HTTPRequest.new()
	request.timeout = 6.0
	request.body_size_limit = 4096
	owner.add_child(request)
	var root := OS.get_environment("UMAMU_ACCOUNT_PORT")
	var api_root := DEFAULT_ROOT if root.is_empty() else "http://127.0.0.1:%s/api/" % root
	var endpoint: String = get_script().resource_path.get_file().get_basename().replace("-", "").trim_suffix("message")
	var started := request.request(api_root + endpoint, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify({"username": username, "password": password}))
	password = ""
	if started != OK:
		request.queue_free()
		return {"error": "Could not reach the account server."}
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Account server unavailable. Start it or play as a guest."}
	var body: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if body is Dictionary:
		if response[1] == 200 and typeof(body.get("username")) == TYPE_STRING:
			return {"username": body["username"]}
		if typeof(body.get("error")) == TYPE_STRING:
			return {"error": body["error"]}
	return {"error": "The account server returned an invalid response."}
