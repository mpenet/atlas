;; ABOUTME: Plugins: Lua or Fennel files listed in the config, loaded when a
;; ABOUTME: profile uses what they provide; for now, functions signing requests.
(local util (require :atlas.util))
(local auth (require :atlas.auth))

(fn fail [path why]
  (error (.. "plugin " path ": " why) 0))

(fn expand-home [path]
  (if (path:match "^~/")
      (.. (or (os.getenv :HOME) "~") (path:sub 2))
      path))

(fn command-output [command]
  (let [h (io.popen command)
        out (when h (h:read :*a))]
    (when h (h:close))
    (or out "")))

(var user-id nil)

(fn check-file [path]
  "Raise unless path is a file of the user's that no one else can change: a
plugin runs with the user's credentials."
  (let [listing (command-output (.. "ls -ldnL " (util.shell-quote path)
                                    " 2>/dev/null"))
        (mode owner) (listing:match "^(%S+)%s+%S+%s+(%d+)")]
    (when (not mode)
      (fail path "not found"))
    (when (not= (mode:sub 1 1) "-")
      (fail path "not a file"))
    (when (not user-id)
      (set user-id (: (command-output "id -u") :match "%d+")))
    (when (not= owner user-id)
      (fail path "belongs to another user"))
    (when (or (= (mode:sub 6 6) :w) (= (mode:sub 9 9) :w))
      (fail path (.. "can be changed by other users, who would get your credentials (chmod go-w "
                     path ")")))))

(fn evaluate [path]
  "What the plugin file at path returns."
  (if (path:match "%.fnl$")
      (let [fennel (require :fennel)]
        (fennel.dofile path {:filename path}))
      (path:match "%.lua$")
      (let [(chunk err) (loadfile path :t)]
        (if chunk (chunk) (error err 0)))
      (fail path "must be a .lua or .fnl file")))

(local loaded {})

(fn load-plugin [path]
  "The table the plugin at path returns, checked; loaded once."
  (or (. loaded path) (do
                        (check-file path)
                        (let [(ok plugin) (pcall evaluate path)]
                          (when (not ok)
                            (fail path (tostring plugin)))
                          (when (not= (type plugin) :table)
                            (fail path
                                  "must return a table, like {:auth {:name function}}"))
                          (when (not (or (= nil plugin.auth)
                                         (= (type plugin.auth) :table)))
                            (fail path "auth must be a table of functions"))
                          (each [name f (pairs (or plugin.auth {}))]
                            (when (not= (type f) :function)
                              (fail path
                                    (.. "auth " (tostring name)
                                        " must be a function")))
                            (when (auth.built-in? name)
                              (fail path (.. "auth " name " is built in"))))
                          (tset loaded path plugin)
                          plugin))))

(fn plugin-paths [config]
  (icollect [_ p (ipairs (or config.plugins []))]
    (expand-home p)))

(fn resolve-auth [config auth-config]
  "auth-config as is when atlas knows its name; else a copy with :sign, the
function of the config's plugins that provides it, and :plugin, its file.
Plugins are only loaded for an auth that isn't built in."
  (if (auth.built-in? auth-config.name)
      auth-config
      (let [found (accumulate [found nil _ path (ipairs (plugin-paths config))]
                    (let [f (?. (load-plugin path) :auth auth-config.name)]
                      (when (and f found)
                        (error (.. "auth '" auth-config.name
                                   "' is provided by two plugins: " found.path
                                   " and " path)
                               0))
                      (if f {: f : path} found)))]
        (when (not found)
          (error (.. "auth '" (tostring auth-config.name)
                     "' is not built in, and no plugin provides it")
                 0))
        (doto (collect [k v (pairs auth-config)] k v)
          (tset :sign found.f)
          (tset :plugin found.path)))))

{: resolve-auth}
