# CKA Practice (Simple Edition)

Straightforward CKA practice labs derived from the CKA-PREP playlist. Every question lives in its own folder with three bash files:

- `LabSetUp.bash` � copy/paste into Killercoda (or any Kubernetes cluster) to prep the environment.
- `Questions.bash` � the scenario text plus the YouTube link for the walkthrough.
- `SolutionNotes.bash` � a step-by-step solution when you need a hint.
- `Verify.bash` � an automated check used by `scripts/finish-test.sh` to grade whether the question was solved correctly.

## How to Use
1. Launch the CKA Killercoda playground or your own cluster.
2. Clone this repo inside the environment.
3. Run `./install.sh` once (it's executable, `chmod +x` already set in git). This installs a system-wide `cka` command at `/usr/bin/cka`, so you can run `cka <number>` / `cka finish` from any directory, instead of always typing `./scripts/run-question.sh` / `./scripts/finish-test.sh`. If `/usr/bin` isn't writable by your user (not needed on Killercoda, which runs as root), it falls back to `sudo` automatically.
4. Pick a folder under `Question-*`.
5. Run `cka 1` (or the full folder name, e.g. `cka "Question-9 Cri-Dockerd"`) to reset the cluster, apply the setup and print the question text. This is equivalent to running `./scripts/run-question.sh 1` directly if you prefer not to install the `cka` command, or `bash Question-01/LabSetUp.bash` manually. The very first question you run in a session starts a timer (mirroring the real CKA's 2-hour limit).
   - When the timer starts (first question of the session), if you're **outside** `tmux`, `run-question.sh` automatically opens a `tmux` session (`cka-exam`) split horizontally into 2 panes (top/bottom), like a regular layout: the bottom pane runs the question itself, while the top pane is further split vertically (side by side) into the question's descriptive text on the left and a narrower pane on the right running `./scripts/show-timer.sh`, then attaches you to it. If you're **already inside** `tmux`, it instead opens that same top row (question text + timer) above your current window. Either way, mouse mode and a bigger scrollback buffer are enabled for that `tmux` session so scrolling (e.g. while editing files with `vim`) works normally in every pane.
6. Work through the task, then consult `SolutionNotes.bash` if you need help.
7. Repeat step 5 for as many questions as you want to attempt in the same practice run.
   - Right before resetting the cluster, `run-question.sh` automatically **pauses the exam timer** (writing `scripts/.session_pause`), so cluster reset + lab setup time is excluded from the exam clock. Once the environment is ready, the timer **resumes automatically**, accumulating the paused duration in `scripts/.session_paused_total`. `show-timer.sh` reflects this live with a `Status: PAUSED` / `Status: RESUMED` / `Status: RUNNING` line, and `finish-test.sh` also subtracts the total paused time from the final elapsed time shown.
   - Right before resetting the cluster for the next question, `run-question.sh` automatically runs the `Verify.bash` of the question you just left and caches its result (`scripts/.session_results`). This way, `finish-test.sh` can still grade that question correctly later even though its objects get wiped by the reset — only the question you're currently working on (not yet cached) is checked live against the cluster.
8. When you're done, run `cka finish` (or `./scripts/finish-test.sh` directly) to end the test. It stops the timer and shows the elapsed time against the 2-hour CKA limit, grades the score over **all 17 questions of the exam** (via each question's `Verify.bash`) — any question you didn't attempt counts as wrong, just like leaving a question blank in the real CKA — shows your score as a percentage (same style as the real CKA), compares it against the passing score (66%), suggests a 75-80%+ practice target for a safety margin on exam day, breaks down your score by the official CKA domain weights (Troubleshooting 30%, Cluster Architecture/Installation/Configuration 25%, Services & Networking 20%, Workloads & Scheduling 15%, Storage 10%), and lists which questions you got right/wrong and why.

## Available Questions
| Question | Topic | Video |
|----------|-------|-------|
| Question-01 | Install Argo CD using Helm without CRDs | https://youtu.be/8GzJ-x9ffE0 |

More questions can be added by copying the template folder and dropping in the three bash files from the original collection.
