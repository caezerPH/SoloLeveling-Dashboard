// Both values are public by design and safe in a repository.
//
// The anon key is what the browser must send to reach the API at all. On its own
// it reads nothing: every table is behind row-level security that requires a real
// session, signup is disabled at the project level, and get_source() is revoked
// from anon outright. Verified by probing the live project with this exact key --
// catalogue [], sources [], get_source 401.
//
// The service_role key is the one that matters, and it is never here. It lives in
// a .env outside this repository and is read only by tools/import.py.
window.PORTAL = {
  SUPABASE_URL: "https://xqrmsbfbtvfgfgnbsflh.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhxcm1zYmZidHZmZ2ZnbmJzZmxoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMwOTY2OTMsImV4cCI6MjEwODY3MjY5M30.iBtLOsQ6ZM6uD5zv9yd-p5QCROmk81PdDWvzOihtuxs",
};
