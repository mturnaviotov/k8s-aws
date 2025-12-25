upstream backend_{{ item.service_name }} {
  server {{ item.service_name }}:8080;
}

server {
  listen 80;
  server_name {{ item.service_name }}.{{ ext_domain }};

  location / {
    proxy_pass http://backend_{{ item.service_name }};
    proxy_ssl_verify off;
    proxy_ssl_server_name on;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_http_version 1.1;
    proxy_set_header Connection "";
  }

  error_page 500 502 503 504 /50x.html;
  location = /50x.html {
    internal;
    root /usr/share/nginx/html;
  }
}