#!/usr/local/bin/ruby
#-*- encoding: utf-8 -*-
########## (C) 2024 QLABO Ltd. ##########
#
# simple udp relay for snmp
# snmp監視を、中継ホスト経由で試す程度の利用を想定。
# UDPの中継処理についてよくわからず書いており、コードは単なるご参考程度に。
#

require 'socket'
require 'optparse'

def write_data_dump(f,data)
  str=Array.new
  data.split(//).each{|c|
    if c.ord<32 || c.ord>=127
      str<<"[#{c.ord.to_s(16)}]"
    else
      str<<c
    end
  }
  f.puts str.join
end

listen_port=relay_to =nil
options=Hash.new
ARGV.push("-h") if ARGV.empty?
OptionParser.new do |opt|
  opt.on('-d <FILENAME>','--debugfile <FILENAME>',' debug file') {|v|options[:debugfile] = v}
  opt.banner+=" listen_port relay_to_ip:port [-o debugfile]\n"
  listen_port,relay_to =opt.parse(ARGV)
end

relay_to_ip = relay_to.to_s.split(":")[0]
relay_to_port = relay_to.to_s.split(":")[1].to_i

if relay_to_port==0
  print "Usage... "+$0+" port relay_ip:relay_port [-d debug_fle]"
  exit
end
clientsock = UDPSocket.new
clientsock.bind("", listen_port)

fin=fout=fdebug=nil
if options[:debugfile]
  fin=open(options[:debugfile]+".in","wb")
  fout=open(options[:debugfile]+".out","wb")
  fdebug=open(options[:debugfile]+".debug","w")
end

loop do
  data, addr = clientsock.recvfrom(65535)
  afinet,client_port,client_ip=addr
  child_pid=fork do
    destsock=UDPSocket.new
    destsock.send(data,0, relay_to_ip, relay_to_port)
    if options[:debugfile]
      fout.write(data) 
      fdebug.puts "\n>>> relay #{relay_to_ip} #{relay_to_port} from #{destsock.local_address.ip_address}:#{destsock.local_address.ip_port}\n"
      write_data_dump(fdebug,data)
    end
    response=Array.new
    while select [destsock], nil, nil, 0.01 #多分1回で済むloop
      response << destsock.recv(65535)
    end
    response.each{|data|
      clientsock.send(data, 0, client_ip, client_port)
      if options[:debugfile]
        fin.write(data) 
        fdebug.puts "\n<<< reply #{client_ip} #{client_port}\n"
        write_data_dump(fdebug,data)
      end
    }
    exit
  end
  Process.detach(child_pid)
end

if options[:debugfile]
  fin.close 
  fout.close
  fdebug.close
end
