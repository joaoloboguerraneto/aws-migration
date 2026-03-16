package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"time"
)

// ─────────────────────────────────────────────
// Stopwatch
// ─────────────────────────────────────────────

type Stopwatch struct {
	mu        sync.RWMutex
	ID        string
	StartTime *time.Time
	Elapsed   time.Duration
	Running   bool
	Laps      []Lap
}

type Lap struct {
	Number   int    `json:"number"`
	Duration string `json:"duration"`
	Total    string `json:"total"`
	TotalMs  int64  `json:"total_ms"`
}

type StopwatchJSON struct {
	ID        string `json:"id"`
	Elapsed   string `json:"elapsed"`
	ElapsedMs int64  `json:"elapsed_ms"`
	Running   bool   `json:"running"`
	Laps      []Lap  `json:"laps"`
}

func (sw *Stopwatch) currentElapsed() time.Duration {
	if sw.Running && sw.StartTime != nil {
		return sw.Elapsed + time.Since(*sw.StartTime)
	}
	return sw.Elapsed
}

func (sw *Stopwatch) Start() {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	if !sw.Running {
		now := time.Now()
		sw.StartTime = &now
		sw.Running = true
	}
}

func (sw *Stopwatch) Stop() {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	if sw.Running && sw.StartTime != nil {
		sw.Elapsed += time.Since(*sw.StartTime)
		sw.StartTime = nil
		sw.Running = false
	}
}

func (sw *Stopwatch) Reset() {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	sw.StartTime = nil
	sw.Elapsed = 0
	sw.Running = false
	sw.Laps = nil
}

func (sw *Stopwatch) RecordLap() {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	total := sw.currentElapsed()
	var lastTotal time.Duration
	if len(sw.Laps) > 0 {
		lastTotal = time.Duration(sw.Laps[len(sw.Laps)-1].TotalMs) * time.Millisecond
	}
	sw.Laps = append(sw.Laps, Lap{
		Number:   len(sw.Laps) + 1,
		Duration: fmtDur(total - lastTotal),
		Total:    fmtDur(total),
		TotalMs:  total.Milliseconds(),
	})
}

func (sw *Stopwatch) ToJSON() StopwatchJSON {
	sw.mu.RLock()
	defer sw.mu.RUnlock()
	elapsed := sw.currentElapsed()
	laps := sw.Laps
	if laps == nil {
		laps = []Lap{}
	}
	return StopwatchJSON{
		ID:        sw.ID,
		Elapsed:   fmtDur(elapsed),
		ElapsedMs: elapsed.Milliseconds(),
		Running:   sw.Running,
		Laps:      laps,
	}
}

func fmtDur(d time.Duration) string {
	ms := d.Milliseconds()
	return fmt.Sprintf("%02d:%02d.%03d", ms/60000, (ms%60000)/1000, ms%1000)
}

// ─────────────────────────────────────────────
// Store
// ─────────────────────────────────────────────

type Store struct {
	mu sync.RWMutex
	sw map[string]*Stopwatch
}

func NewStore() *Store {
	return &Store{sw: make(map[string]*Stopwatch)}
}

func (s *Store) GetOrCreate(id string) *Stopwatch {
	s.mu.Lock()
	defer s.mu.Unlock()
	if sw, ok := s.sw[id]; ok {
		return sw
	}
	sw := &Stopwatch{ID: id}
	s.sw[id] = sw
	return sw
}

// ─────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────

var store = NewStore()

func writeJSON(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()

	// Kubernetes probes
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ok") })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprint(w, "ready") })

	// Clock API
	mux.HandleFunc("GET /api/clock", func(w http.ResponseWriter, _ *http.Request) {
		now := time.Now().UTC()
		writeJSON(w, map[string]any{
			"utc":       now.Format(time.RFC3339),
			"time":      now.Format("15:04:05"),
			"date":      now.Format("2006-01-02"),
			"timestamp": now.Unix(),
		})
	})

	// Stopwatch API
	mux.HandleFunc("GET /api/stopwatch/{id}", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, store.GetOrCreate(r.PathValue("id")).ToJSON())
	})
	mux.HandleFunc("POST /api/stopwatch/{id}/start", func(w http.ResponseWriter, r *http.Request) {
		sw := store.GetOrCreate(r.PathValue("id"))
		sw.Start()
		writeJSON(w, sw.ToJSON())
	})
	mux.HandleFunc("POST /api/stopwatch/{id}/stop", func(w http.ResponseWriter, r *http.Request) {
		sw := store.GetOrCreate(r.PathValue("id"))
		sw.Stop()
		writeJSON(w, sw.ToJSON())
	})
	mux.HandleFunc("POST /api/stopwatch/{id}/reset", func(w http.ResponseWriter, r *http.Request) {
		sw := store.GetOrCreate(r.PathValue("id"))
		sw.Reset()
		writeJSON(w, sw.ToJSON())
	})
	mux.HandleFunc("POST /api/stopwatch/{id}/lap", func(w http.ResponseWriter, r *http.Request) {
		sw := store.GetOrCreate(r.PathValue("id"))
		sw.RecordLap()
		writeJSON(w, sw.ToJSON())
	})

	// Web UI
	mux.HandleFunc("GET /", serveUI)

	log.Printf("Stopwatch + Clock running on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func serveUI(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, htmlUI)
}

const htmlUI = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Stopwatch & Clock</title>
<style>
:root{--bg:#0b0f1a;--sf:#131928;--bd:#1e2a42;--tx:#e2e8f0;--mt:#64748b;--ac:#22d3ee;--dn:#f87171;--ok:#4ade80}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'SF Mono','Cascadia Code','Fira Code',monospace;background:var(--bg);color:var(--tx);min-height:100vh;display:flex;flex-direction:column;align-items:center;padding:40px 20px}
h1{font-size:13px;font-weight:400;color:var(--mt);letter-spacing:4px;text-transform:uppercase;margin-bottom:36px}
.tabs{display:flex;gap:2px;background:var(--sf);border-radius:10px;padding:3px;margin-bottom:36px}
.tab{padding:8px 28px;border:none;background:0;color:var(--mt);font:inherit;font-size:13px;cursor:pointer;border-radius:8px;transition:.2s}
.tab.active{background:var(--bd);color:var(--ac)}
.panel{display:none;text-align:center;width:100%;max-width:440px}
.panel.active{display:block}

/* Clock */
.clock-time{font-size:68px;font-weight:200;letter-spacing:3px;font-variant-numeric:tabular-nums;background:linear-gradient(135deg,var(--ac),#a78bfa);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.clock-secs{font-size:24px;color:var(--mt);margin-top:4px;font-variant-numeric:tabular-nums}
.clock-date{font-size:15px;color:var(--mt);margin-top:14px}
.clock-utc{font-size:11px;color:var(--bd);margin-top:6px}

/* Stopwatch */
.sw-time{font-size:60px;font-weight:200;letter-spacing:2px;font-variant-numeric:tabular-nums;margin-bottom:28px;transition:color .2s}
.sw-time.on{color:var(--ok)}
.btns{display:flex;gap:12px;justify-content:center;margin-bottom:28px}
.btn{width:50px;height:50px;border-radius:50%;border:1.5px solid var(--bd);background:var(--sf);color:var(--tx);font-size:17px;cursor:pointer;display:flex;align-items:center;justify-content:center;transition:.15s}
.btn:hover{border-color:var(--ac);transform:scale(1.08)}
.btn.p{border-color:var(--ac);color:var(--ac)}
.btn.d{border-color:var(--dn);color:var(--dn)}
.laps{width:100%}
.lap{display:flex;justify-content:space-between;padding:9px 0;border-bottom:1px solid var(--bd);font-size:13px;color:var(--mt)}
.lap-n{color:var(--tx);min-width:56px;text-align:left}
.lap-t{font-variant-numeric:tabular-nums}

.foot{margin-top:auto;padding-top:40px;font-size:11px;color:var(--bd);text-align:center}
.foot a{color:var(--mt);text-decoration:none}
@media(max-width:480px){.clock-time{font-size:44px}.sw-time{font-size:40px}}
</style>
</head>
<body>
<h1>DevOps Challenge</h1>
<div class="tabs">
  <button class="tab active" onclick="go('clock')">Clock</button>
  <button class="tab" onclick="go('sw')">Stopwatch</button>
</div>

<div id="p-clock" class="panel active">
  <div class="clock-time" id="c-hm">--:--</div>
  <div class="clock-secs" id="c-s">--</div>
  <div class="clock-date" id="c-date"></div>
  <div class="clock-utc" id="c-utc"></div>
</div>

<div id="p-sw" class="panel">
  <div class="sw-time" id="sw-d">00:00.000</div>
  <div class="btns">
    <button class="btn p" onclick="A('start')" title="Start">&#9654;</button>
    <button class="btn" onclick="A('stop')" title="Pause">&#10074;&#10074;</button>
    <button class="btn" onclick="A('lap')" title="Lap">&#9711;</button>
    <button class="btn d" onclick="A('reset')" title="Reset">&#10226;</button>
  </div>
  <div class="laps" id="laps"></div>
</div>

<div class="foot">
  Go app on Kubernetes &middot; Prometheus + Grafana<br>
  <a href="/healthz">/healthz</a> &middot;
  <a href="/api/clock">/api/clock</a> &middot;
  <a href="/api/stopwatch/default">/api/stopwatch</a>
</div>

<script>
function go(t){
  document.querySelectorAll('.tab').forEach((b,i)=>{b.classList.toggle('active',i===(t==='clock'?0:1))});
  document.getElementById('p-clock').classList.toggle('active',t==='clock');
  document.getElementById('p-sw').classList.toggle('active',t==='sw');
}

// Clock
function tick(){
  const n=new Date();
  document.getElementById('c-hm').textContent=String(n.getHours()).padStart(2,'0')+':'+String(n.getMinutes()).padStart(2,'0');
  document.getElementById('c-s').textContent=String(n.getSeconds()).padStart(2,'0');
  document.getElementById('c-date').textContent=n.toLocaleDateString('en-US',{weekday:'long',year:'numeric',month:'long',day:'numeric'});
  document.getElementById('c-utc').textContent=n.toISOString().replace('T',' ').split('.')[0]+' UTC';
}
setInterval(tick,200);tick();

// Stopwatch
let pi;
async function A(a){
  const r=await fetch('/api/stopwatch/default/'+a,{method:a==='default'?'GET':'POST'});
  const d=await r.json();R(d);
  if(a==='start'){clearInterval(pi);pi=setInterval(async()=>{const r2=await fetch('/api/stopwatch/default');R(await r2.json())},50)}
  if(a==='stop'||a==='reset')clearInterval(pi);
}
function R(d){
  const el=document.getElementById('sw-d');
  el.textContent=d.elapsed;
  el.className='sw-time'+(d.running?' on':'');
  document.getElementById('laps').innerHTML=(d.laps||[]).slice().reverse().map(l=>
    '<div class="lap"><span class="lap-n">Lap '+l.number+'</span><span class="lap-t">'+l.duration+'</span><span class="lap-t">'+l.total+'</span></div>'
  ).join('');
}
fetch('/api/stopwatch/default').then(r=>r.json()).then(R).catch(()=>{});
</script>
</body>
</html>`