[control_plane]
%{ for i, ip in control_plane_ips ~}
cp_node${i + 1} ansible_host=${ip} ansible_connection=ssh ansible_user=ubuntu
%{ endfor ~}

[workers]
%{ for i, ip in worker_ips ~}
worker${i + 1} ansible_host=${ip} ansible_connection=ssh ansible_user=ubuntu
%{ endfor ~}

[k8s_cluster:children]
control_plane
workers