# Install and run cri-dockerd
# Use the absolute path, since LabSetUp.bash always downloads the package to
# /root/cri-dockerd.deb, regardless of the directory this script is run from
# (e.g. ~/cka/sandbox).
sudo dpkg -i /root/cri-dockerd.deb
sudo systemctl daemon-reload
sudo systemctl enable --now cri-docker.service
# Give systemd a brief moment to actually bring the service up before
# checking its status, so an immediate verification right after this script
# doesn't catch it mid-start and report a false failure.
sleep 2
sudo systemctl status cri-docker.service --no-pager || true
sudo systemctl is-active cri-docker.service

# Set sysctl (make persistent)
sudo tee /etc/sysctl.d/kube.conf >/dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables=1
net.ipv6.conf.all.forwarding=1
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_max=131072
EOF
sudo sysctl --system
