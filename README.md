# fivem-smart-utilities

📦 Project Prompt for Google Jules
Title: Smart City Utilities System — Complete FiveM Resource

🧠 Objective:
Build a fully functional, optimized FiveM resource that simulates a Smart City Utilities System, covering:

⚡ Power grid

💧 Water supply

🌐 Internet (fiber)

♻️ Trash and sanitation services

It must include:

🧠 Modular Lua code (client/server/config)

📱 Tablet-style NUI dashboard with Tailwind CSS + Vanilla JS

🧩 Optimized fxmanifest.lua

⚙️ oxmysql async queries

🔄 Sync & event system

📉 Performance: idle/active resmon ≤ 0.02ms

✅ README + install steps

🧱 Tech Stack:
Component	Tech
Code	Lua
Frontend (UI)	HTML + Tailwind CSS + Vanilla JavaScript (NUI)
Database	oxmysql
Framework	QBCore-compatible
Build Target	FiveM server with 100+ concurrent players

📁 Required Folder Structure
css
Copy
Edit
[fivem-smart-utilities]
│
├── fxmanifest.lua
├── config.lua
├── client.lua
├── server.lua
├── utils/
│   └── logger.lua
├── html/
│   ├── index.html
│   ├── style.css (Tailwind)
│   ├── script.js
├── images/
└── README.md
🔧 Features per Module
Power:

Substations per zone

Blackouts, repairs, sabotage

Power affects traffic lights, ATMs, buildings

Water:

Random leaks, meter install

Puddle effects, criminal water theft

Billing system

Internet:

Fiber install, service tiers

Required for CCTV, bank, etc.

Hackable by criminals

Trash:

Garbage collection job

Illegal dumping detection

Weight-based rewards

📊 Performance Goals
Use SetTimeout or local cache (avoid heavy loops)

StateBag / PolyZone support

Idle resmon ≤ 0.01ms, max active ≤ 0.02ms

Client-server separation + efficient event triggers

📤 Admin & Dev Support
Commands like /forceblackout, /repairleak, /deployfiber

exports[] support for dev integration

Config toggles for timers, zones, prices

Easy compatibility with other RP scripts (housing, jobs, crime)

🧪 Testing Tasks (Optional)
Simulate leak, power outage, and response

Admin UI to visualize all zones

Chart.js integration for tablet graphs (optional)

Clean NUI with quadrant layout (see attached image or follow tablet-style layout)

✅ Deliverables
Fully working FiveM script with all modules

UI integrated and styled for tablet use

README with full install/config instructions

Tested and optimized with resmon benchmarks

📝 Notes
This is meant for a production-grade RP server and should be clean, modular, and maintainable.
