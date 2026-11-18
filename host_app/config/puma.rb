threads_count = ENV.fetch("RAILS_MAX_THREADS", 5)
threads threads_count, threads_count
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 7470)}"
plugin :solid_queue
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")
