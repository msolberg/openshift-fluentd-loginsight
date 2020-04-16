require 'json'
require 'net/http'
require 'uri'

def set_header(req)
  if @serializer == 'json'
    set_json_header(req)
  end
  req
end

def set_json_header(req)
  req['Content-Type'] = 'application/json'
  req
end

def send_request(req, uri)
  if @auth and @auth.to_s.eql? "basic"
    req.basic_auth(@username, @password)
  end
  begin
    retries ||= 2
    response = nil
    @last_request_time = Time.now.to_f

    http_conn = Net::HTTP.new(uri.host, uri.port)
    # For debugging, set this
    http_conn.set_debug_output($stdout) if @http_conn_debug
    http_conn.use_ssl = (uri.scheme == 'https')
    if http_conn.use_ssl?
      http_conn.ca_file = @ca_file
    end
    http_conn.verify_mode = @ssl_verify_mode

    response = http_conn.start do |http|
      http.read_timeout = @request_timeout
      http.request(req)
    end
  rescue => e # rescue all StandardErrors
    # server didn't respond
    # Be careful while turning on below log, if LI instance can't be reached and you're sending
    # log-container logs to LI as well, you may end up in a cycle.
    # TODO handle the cyclic case at plugin level if possible.
    # $log.warn "Net::HTTP.#{req.method.capitalize} raises exception: " \
    #   "#{e.class}, '#{e.message}', \n Request: #{req.body[1..1024]}"
    retry unless (retries -= 1).zero?
    raise e if @raise_on_error
  else
    unless response and response.is_a?(Net::HTTPSuccess)
        res_summary = if response
                         "Response Code: #{response.code}\n"\
                         "Response Message: #{response.message}\n" \
                         "Response Body: #{response.body}"
                      else
                        "Response = nil"
                      end
        # ditto cyclic warning
        #print "Failed to #{req.method} #{uri}\n(#{res_summary})\n" \
        #  "Request Size: #{req.body.size} Request Body: #{req.body}"
     end #end unless
  end # end begin
end # end send_request

def send_events(uri, events)
  req = Net::HTTP.const_get(@http_method.to_s.capitalize).new(uri.path)
  
  event_req = {
    "events" => events
  }
  req.body = event_req.to_json
  set_header(req)
  send_request(req, uri)
end


@http_method = "post"
@raise_on_error = true
@auth = "basic"
@username = "username"
@password = "password"
@http_conn_debug = true
@ssl_verify_mode = OpenSSL::SSL::VERIFY_NONE

uri = URI.parse("https://192.168.1.30:9543/api/v1/events/ingest/aexample-uuid-4b7a-8b09-fbfac4b46fd9")
events = JSON.parse(File.read("events.json"))

send_events(uri, events)


