# Debug Reference

## Port Debugging

### Check if a Port is in Use

**Most useful (shows process and PID):**
```bash
lsof -i :3000
```

**Alternative with netstat:**
```bash
netstat -an | grep 3000
```

**Test if port is listening:**
```bash
nc -zv localhost 3000
```

**Show all listening ports:**
```bash
lsof -i -P | grep LISTEN
```

### Kill Process Using a Port

**Quick one-liner:**
```bash
lsof -ti :3000 | xargs kill
```

**Force kill (if process won't terminate):**
```bash
lsof -ti :3000 | xargs kill -9
```

**Manual method:**
```bash
# 1. Find the PID
lsof -i :3000

# 2. Kill using the PID from output
kill <PID>
```

**Example output from `lsof -i :3000`:**
```
COMMAND   PID   USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
node    12345  amine   23u  IPv4 0x...      0t0  TCP *:3000 (LISTEN)
```
Then run: `kill 12345`
