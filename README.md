# CKA Practice (Simple Edition)

Straightforward CKA practice labs derived from the CKA-PREP playlist. Every question lives in its own folder with three bash files:

- `LabSetUp.bash` � copy/paste into Killercoda (or any Kubernetes cluster) to prep the environment.
- `Questions.bash` � the scenario text plus the YouTube link for the walkthrough.
- `SolutionNotes.bash` � a step-by-step solution when you need a hint.
- `Verify.bash` � an automated check used by `scripts/finish-test.sh` to grade whether the question was solved correctly.

## How to Use
1. Launch the CKA Killercoda playground or your own cluster.
2. Clone this repo inside the environment.
3. Pick a folder under `Question-*`.
4. Run `./scripts/run-question.sh 1` (or the full folder name, e.g. `scripts/run-question.sh "Question-9 Cri-Dockerd"`) to reset the cluster, apply the setup and print the question text, or run `bash Question-01/LabSetUp.bash` manually. The very first question you run in a session starts a timer (mirroring the real CKA's 2-hour limit).
5. Work through the task, then consult `SolutionNotes.bash` if you need help.
6. Repeat step 4 for as many questions as you want to attempt in the same practice run.
7. When you're done, run `./scripts/finish-test.sh` to end the test. It stops the timer and shows the elapsed time against the 2-hour CKA limit, grades every question you attempted (via each question's `Verify.bash`), shows your score as a percentage (same style as the real CKA), compares it against the passing score (66%), tells you if you passed, and lists which questions you got right/wrong and why.

## Available Questions
| Question | Topic | Video |
|----------|-------|-------|
| Question-01 | Install Argo CD using Helm without CRDs | https://youtu.be/8GzJ-x9ffE0 |

More questions can be added by copying the template folder and dropping in the three bash files from the original collection.
