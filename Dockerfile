FROM nginx
RUN rm -rf /usr/share/nginx/html/index.html
RUN echo "<h1>Hi, I am version 0.0.2</h1>" > /usr/share/nginx/html/index.html