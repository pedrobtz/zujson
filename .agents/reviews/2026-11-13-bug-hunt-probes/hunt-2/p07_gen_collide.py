# Build keys whose FNV-1a hashes agree in the low 24 bits (Joux multicollision):
# the low k bits of FNV-1a state depend only on the low k bits of the previous state.
import sys, itertools, json
M=(1<<64)-1; P=1099511628211; BITS=24; mask=(1<<BITS)-1
def step(h, bs):
    for b in bs:
        h = ((h ^ b) * P) & M
    return h
alpha = b"abcdefghijklmnopqrstuvwxyz0123456789"
h = 14695981039346656037
stages = int(sys.argv[1])
pairs = []
for s in range(stages):
    seen = {}
    for blk in itertools.product(alpha, repeat=4):
        v = step(h, blk) & mask
        if v in seen:
            a = seen[v]; pairs.append((bytes(a), bytes(blk))); h = step(h, blk) & mask  # only low bits matter from here
            break
        seen[v] = blk
keys = [b""]
for a, b in pairs:
    keys = [k + a for k in keys] + [k + b for k in keys]
# verify
hs = {step(14695981039346656037, k) & mask for k in keys}
assert len(hs) == 1 and len(set(keys)) == len(keys)
def emit(path, ks):
    with open(path, "wb") as f:
        f.write(b'[{' + b','.join(b'"' + k + b'":1' for k in ks) + b'}]')
emit(sys.argv[2], keys)
# honest control: same count, same length, distinct random-ish keys
import hashlib
ctl = [hashlib.sha256(k).hexdigest()[:len(k)].encode() for k in keys]
assert len(set(ctl)) == len(ctl)
emit(sys.argv[3], ctl)
print(len(keys), "keys of", len(keys[0]), "bytes")
