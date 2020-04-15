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
        print "Failed to #{req.method} #{uri}\n(#{res_summary})\n" \
          "Request Size: #{req.body.size} Request Body: #{req.body[1..1024]}"
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


uri = URI.parse("http://localhost/test")
events = [{
            "fields"=> [
                       {"name" => "_stream_id", "content" => "e371e115096943599b9900415950045c"},
                       {"name" => "_systemd_invocation_id", "content" => "ce6b280f6ab545d99efa975251cac67b"},
                       {"name" => "systemd_t_boot_id", "content" => "1843a41638924fa89320fae1dcde0acd"},
                       {"name" => "systemd_t_cap_effective", "content" => "3fffffffff"},
                       {"name" => "systemd_t_cmdline", "content" => "/usr/bin/hyperkube kubelet --config=/etc/kubernetes/kubelet.conf --bootstrap-kubeconfig=/etc/kubernetes/kubeconfig --rotate-certificates --kubeconfig=/var/lib/kubelet/kubeconfig --container-runtime=remote --container-runtime-endpoint=/var/run/crio/crio.sock --node-labels=node-role.kubernetes.io/master,node.openshift.io/os_id=rhcos --minimum-container-ttl-duration=6m0s --cloud-provider=vsphere --volume-plugin-dir=/etc/kubernetes/kubelet-plugins/volume/exec --register-with-taints=node-role.kubernetes.io/master=:NoSchedule --v=3"},
                       {"name" => "systemd_t_comm", "content" => "hyperkube"},
                       {"name" => "systemd_t_exe", "content" => "/usr/bin/hyperkube"},
                       {"name" => "systemd_t_gid", "content" => "0"}
                      ]
}]

send_events(uri, events)


