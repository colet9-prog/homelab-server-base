#!/bin/sh
# Pulls the Canvas calendar feed so Homepage can show it. The feed URL is private, so it is not committed.
curl -sf -o /home/thomasserver/ical/www/canvas.tmp "<your private Canvas calendar feed URL>" \
  && mv /home/thomasserver/ical/www/canvas.tmp /home/thomasserver/ical/www/canvas.ics
