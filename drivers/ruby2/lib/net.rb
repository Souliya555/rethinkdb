# Copyright 2010-2012 RethinkDB, all rights reserved.
require 'socket'
require 'thread'

module RethinkDB
  class RQL
    @@default_conn = nil
    def self.set_default_conn c; @@default_conn = c; end
    def run(c=@@default_conn, opts=nil)
      unbound_if !@body
      c, opts = @@default_conn, c if opts.nil? && c.class != RethinkDB::Connection
      opts = {} if opts.nil?
      opts = {opts => true} if opts.class != Hash
      if !c
        raise ArgumentError, "No connection specified!\n" \
        "Use `query.run(conn)` or `conn.repl(); query.run`."
      end
      c.run(@body, opts)
    end
  end

  class Cursor
    include Enumerable
    def out_of_date # :nodoc:
      @conn.conn_id != @conn_id
    end

    def inspect # :nodoc:
      state = @run ? "(exhausted)" : "(enumerable)"
      extra = out_of_date ? " (Connection #{@conn.inspect} reset!)" : ""
      "#<RethinkDB::Cursor:#{self.object_id} #{state}#{extra}: #{@msg.inspect}>"
    end

    def initialize(results, msg, connection, token) # :nodoc:
      @results = results
      @msg = msg
      @run = false
      @conn_id = connection.conn_id
      @conn = connection
      @token = token
    end

    def each (&block) # :nodoc:
      raise RuntimeError, "Can only iterate over Query_Results once!" if @run
      @run = true
      raise RuntimeError, "Connection has been reset!" if out_of_date
      while true
        @results.each(&block)
        q = Query2.new
        q.type = Query2::QueryType::CONTINUE
        q.query = @msg
        q.token = @token
        res = @conn.run_internal q
        if res.type == Response2::ResponseType::SUCCESS_PARTIAL
          @results = Shim.response_to_native(res, @msg)
        else
          @results = Shim.response_to_native(res, @msg)
          @results.each(&block)
          return self
        end
      end
    end
  end

  class Connection
    def repl; RQL.set_default_conn self; end

    def initialize(host='localhost', port=28015, default_db=nil)
      # begin
      #   @abort_module = ::IRB
      # rescue NameError => e
      #   @abort_module = Faux_Abort
      # end
      @@last = self
      @host = host
      @port = port
      @default_opts = default_db ? {:db => RQL.new.db(default_db)} : {}
      @conn_id = 0
      reconnect
    end
    attr_reader :default_db, :conn_id

    @@token_cnt = 0
    def run_internal q
      dispatch q
      wait q.token
    end
    def run(msg, opts)
      q = Query2.new
      q.type = Query2::QueryType::START
      q.query = msg
      q.token = @@token_cnt += 1

      @default_opts.merge(opts).each {|k,v|
        ap = Query2::AssocPair.new
        ap.key = k.to_s
        ap.val = v.to_pb
        q.global_optargs << ap
      }

      res = run_internal q
      if res.type == Response2::ResponseType::SUCCESS_PARTIAL
        Cursor.new(Shim.response_to_native(res, msg), msg, self, q.token)
      else
        Shim.response_to_native(res, msg)
      end
    end

    def dispatch msg
      PP.pp msg if $DEBUG
      payload = msg.serialize_to_string
      #File.open('sexp_payloads.txt', 'a') {|f| f.write(payload.inspect+"\n")}
      packet = [payload.length].pack('L<') + payload
      @socket.send(packet, 0)
      return msg.token
    end

    def wait token
      res = nil
      raise RuntimeError, "Connection closed by server!" if not @listener
      @mutex.synchronize do
        (@waiters[token] = ConditionVariable.new).wait(@mutex) if not @data[token]
        res = @data.delete token if @data[token]
      end
      raise RuntimeError, "Connection closed by server!" if !@listener or !res
      return res
    end

    # Change the default database of a connection.
    def use(new_default_db)
      @default_opts[:db] = RQL.new.db(new_default_db)
    end

    def inspect
      properties = "(#{@host}:#{@port}) (Default Database: '#{@default_db}')"
      state = @listener ? "(listening)" : "(closed)"
      "#<RethinkDB::Connection:#{self.object_id} #{properties} #{state}>"
    end

    @@last = nil
    @@magic_number = 0x3f61ba36

    def debug_socket; @socket; end

    # Reconnect to the server.  This will interrupt all queries on the
    # server and invalidate all outstanding enumerables on the client.
    def reconnect
      @socket.close if @socket
      @socket = TCPSocket.open(@host, @port)
      @waiters = {}
      @data = {}
      @mutex = Mutex.new
      @conn_id += 1
      start_listener
      self
    end

    def close
      @listener.terminate if @listener
      @listener = nil
      @socket.close
      @socket = nil
    end

    def self.last
      return @@last if @@last
      raise RuntimeError, "No last connection.  Use RethinkDB::Connection.new."
    end

    def start_listener
      class << @socket
        def read_exn(len)
          buf = read len
          if !buf or buf.length != len
            raise RuntimeError, "Connection closed by server."
          end
          return buf
        end
      end
      @socket.send([@@magic_number].pack('L<'), 0)
      @listener.terminate if @listener
      @listener = Thread.new do
        loop do
          begin
            response_length = @socket.read_exn(4).unpack('L<')[0]
            response = @socket.read_exn(response_length)
          rescue RuntimeError => e
            @mutex.synchronize do
              @listener = nil
              @waiters.each {|kv| kv[1].signal}
            end
            Thread.current.terminate
            abort("unreachable")
          end
          #TODO: Recovery
          begin
            protob = Response2.new.parse_from_string(response)
          rescue
            raise RuntimeError, "Bad Protobuf #{response}, server is buggy."
          end
          @mutex.synchronize do
            @data[protob.token] = protob
            if (@waiters[protob.token])
              cond = @waiters.delete protob.token
              cond.signal
            end
          end
        end
      end
    end
  end
end
