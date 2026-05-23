# test/test-integration.janet
# Orchestrates the E2E verification of environment forwarding in multiplexers

(import ../src/fzf)
(import ../src/env)

# Ensure the mock logs directory is clean
(def mock-bin-dir "/tmp/ok-mock-bin")
(os/execute ["mkdir" "-p" mock-bin-dir] :p)
(os/execute ["rm" "-f" 
             (string mock-bin-dir "/zellij.args")
             (string mock-bin-dir "/tmux.args")
             (string mock-bin-dir "/fzf.args")
             (string mock-bin-dir "/kak.args")
             (string mock-bin-dir "/kak.stdin")] :p)

# Write mock scripts
(defn write-mock [name content]
  (def path (string mock-bin-dir "/" name))
  (def f (file/open path :w))
  (:write f content)
  (:close f)
  (os/execute ["chmod" "+x" path] :p))

# Write mock zellij client
(write-mock "zellij" 
  `#!/bin/sh
  echo "$@" >> /tmp/ok-mock-bin/zellij.args
  # Locate the command to execute (everything after --)
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      break
    fi
    shift
  done
  # Scrub mock-bin-dir and repo-dir from PATH to simulate the background daemon environment
  CLEAN_PATH=$(echo "$PATH" | sed -E 's|[^:]*ok-mock-bin[^:]*:?||g; s|[^:]*kak-emporium[^:]*:?||g')
  export PATH="$CLEAN_PATH"
  export XDG_RUNTIME_DIR="/run/user/9999"
  exec "$@"
  `)

# Write mock tmux client
(write-mock "tmux"
  `#!/bin/sh
  echo "$@" >> /tmp/ok-mock-bin/tmux.args
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--" ]; then
      shift
      break
    fi
    shift
  done
  CLEAN_PATH=$(echo "$PATH" | sed -E 's|[^:]*ok-mock-bin[^:]*:?||g; s|[^:]*kak-emporium[^:]*:?||g')
  export PATH="$CLEAN_PATH"
  export XDG_RUNTIME_DIR="/run/user/9999"
  exec "$@"
  `)

# Write mock fzf selection binary
(write-mock "fzf"
  `#!/bin/sh
  echo "$@" >> /tmp/ok-mock-bin/fzf.args
  echo "mock_result_file.txt"
  `)

# Write mock kak client loopback
(write-mock "kak"
  `#!/bin/sh
  echo "$@" >> /tmp/ok-mock-bin/kak.args
  echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >> /tmp/ok-mock-bin/kak.args
  cat - >> /tmp/ok-mock-bin/kak.stdin
  `)

# Write mock ok executable to run src/main.janet directly while keeping mock-bin-dir at the front of PATH
(write-mock "ok"
  `#!/bin/sh
  export PATH="/tmp/ok-mock-bin:$PATH"
  exec janet "/var/home/kgzm/packages/kak-emporium/src/main.janet" "$@"
  `)

# Save original environment
(def orig-path (os/getenv "PATH"))
(def repo-dir (os/cwd))

# Setup test environment simulating a Kakoune session inside Zellij
(os/setenv "PATH" (string mock-bin-dir ":" repo-dir ":" orig-path))
(os/setenv "ZELLIJ_SESSION_NAME" "test-zellij-session")
(os/setenv "XDG_RUNTIME_DIR" "/tmp/kak-runtime-test-123")
(os/setenv "OK_OUTER_XDG_RUNTIME_DIR" "/run/user/1000")
(os/setenv "OK_ZELLIJ_OUT_PATH" (string mock-bin-dir "/zellij.out"))
(os/setenv "OK_ZELLIJ_ERR_PATH" (string mock-bin-dir "/zellij.err"))
(os/setenv "OK_TMUX_OUT_PATH" (string mock-bin-dir "/tmux.out"))
(os/setenv "OK_TMUX_ERR_PATH" (string mock-bin-dir "/tmux.err"))

# Run the test client (Zellij Path)
(print "Running Zellij integration test...")
(fzf/launch "test-session" "test-client" "test find" "files" "find" ".")

# Verify Zellij was invoked and successfully executed the mock pipeline
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/zellij.args"] :p)) "Zellij was invoked")
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/fzf.args"] :p)) "Fzf was invoked (indicates PATH forwarding worked)")
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/kak.args"] :p)) "Kak was invoked (indicates nested callback ran)")

# Verify that kak -p was called with the correct XDG_RUNTIME_DIR
(def kak-args (slurp "/tmp/ok-mock-bin/kak.args"))
(assert (string/find "XDG_RUNTIME_DIR=/tmp/kak-runtime-test-123" kak-args) 
        "XDG_RUNTIME_DIR was correctly forwarded to the callback process under Zellij")

# Verify that the Kakscript command sent back to Kakoune is correct
(def kak-stdin (slurp "/tmp/ok-mock-bin/kak.stdin"))
(assert (string/find "edit './mock_result_file.txt'" kak-stdin)
        "Kakscript selection was correctly sent back to Kakoune under Zellij")

# Reset mock args log files for Tmux path verification
(os/execute ["rm" "-f" 
             (string mock-bin-dir "/zellij.args")
             (string mock-bin-dir "/tmux.args")
             (string mock-bin-dir "/fzf.args")
             (string mock-bin-dir "/kak.args")
             (string mock-bin-dir "/kak.stdin")] :p)

# Setup test environment simulating a Tmux session
(os/setenv "ZELLIJ_SESSION_NAME" nil)
(os/setenv "TMUX" "/tmp/tmux-test/default,123,0")

# Run the test client (Tmux Path)
(print "Running Tmux integration test...")
(fzf/launch "test-session" "test-client" "test find" "files" "find" ".")

# Verify Tmux was invoked and successfully executed the mock pipeline
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/tmux.args"] :p)) "Tmux was invoked")
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/fzf.args"] :p)) "Fzf was invoked under Tmux")
(assert (= 0 (os/execute ["test" "-f" "/tmp/ok-mock-bin/kak.args"] :p)) "Kak was invoked under Tmux")

# Verify that the Kakscript command sent back to Kakoune is correct
(def kak-stdin-tmux (slurp "/tmp/ok-mock-bin/kak.stdin"))
(assert (string/find "edit './mock_result_file.txt'" kak-stdin-tmux)
        "Kakscript selection was correctly sent back to Kakoune under Tmux")

# Cleanup mock directory
(os/execute ["rm" "-rf" mock-bin-dir] :p)
(print "Integration tests passed successfully!")
