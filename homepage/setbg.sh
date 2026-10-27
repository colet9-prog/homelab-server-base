#!/bin/bash
read -rp "Image URL: " URL
URL=$(echo "$URL" | sed -E 's/([?&])w=[0-9]+/\1w=2400/; s/([?&])q=[0-9]+/\1q=80/')
cd ~/homepage || exit 1
mkdir -p images
curl -sL -o images/bg.tmp "$URL"
if [ "$(stat -c%s images/bg.tmp)" -lt 20000 ] || head -c 300 images/bg.tmp | grep -qi "<html"; then
echo "That didn't download as an image. Copy the image address again."
rm -f images/bg.tmp
exit 1
fi
NAME="bg-$(date +%s).jpg"
mv images/bg.tmp "images/$NAME"
find images -name 'bg-*.jpg' ! -name "$NAME" -delete
sudo sed -i "s#image: \"[^\"]*\"#image: \"/images/$NAME\"#" config/settings.yaml
sudo docker restart homepage > /dev/null
echo "Background changed. Hard refresh the dashboard."
