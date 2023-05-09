# sbox_reality
VLESS Reality protocol script based on Sing-box kernel
```shell
wget -N --no-check-certificate https://raw.githubusercontent.com/ziaretguy/sbox_reality/main/reality.sh && bash reality.sh
```

## Debug

# Start
```yaml
systemctl start sing-box
```
# stop
```yaml
systemctl stop sing-box
```
#Forced stop
```yaml
systemctl kill sing-box
```
#restart
```yaml
systemctl restart sing-box
```
#Real-time logging
```yaml
journalctl -u sing-box --output cat -f
```
