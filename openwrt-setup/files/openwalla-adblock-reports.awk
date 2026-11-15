# DNS query correlation and batched SQLite writes. Input includes heartbeat/control records.
function quote(s) { gsub(/'/, "''", s); return "'" s "'" }
function domain_ok(s) { return length(s) <= 253 && s ~ /^[a-z0-9_][a-z0-9_.-]*$/ && s !~ /\.\./ }
function ip_ok(s) { return s ~ /^[0-9a-fA-F:.]+$/ && s ~ /[.:]/ }
function mac_ok(s, a,n,i) {
    n=split(s,a,":"); if(n!=6) return 0
    for(i=1;i<=6;i++) if(a[i] !~ /^[0-9a-fA-F][0-9a-fA-F]$/) return 0
    return 1
}
function forget(k) { if(k in seen) count--; delete seen[k]; delete domains[k]; delete types[k]; delete times[k] }
function begin_batch() { if(!pending) print "BEGIN IMMEDIATE;"; pending++ }
function commit() { if(pending) { print "COMMIT;"; pending=0 }; fflush() }
function metadata(key,value) {
    print "INSERT OR REPLACE INTO metadata(key,value) VALUES(" quote(key) "," quote(value) ");"
}
function policy(path, line,n,a,i,action,last,kind,d) {
    commit(); print "BEGIN IMMEDIATE; DELETE FROM rules;"
    while((getline line < path)>0) {
        sub(/\r$/, "", line); gsub(/^[ \t]+|[ \t]+$/, "", line)
        kind=line; sub(/=.*/, "", kind)
        if(kind=="cname") {
            sub(/^cname=/,"",line); split(line,a,","); d=tolower(a[1])
            if(domain_ok(d)) print "INSERT OR IGNORE INTO rules VALUES(" quote(d) ",0);"
            continue
        }
        if(kind!="local" && kind!="server" && kind!="address") continue
        sub(/^[^=]+=/,"",line); n=split(line,a,"/"); if(n<3 || a[1]!="") continue
        last=a[n]
        if(kind=="address") action=(last=="" || last=="#" || last=="0.0.0.0" || last=="::") ? 1 : 0
        else action=(last=="") ? 1 : 0
        for(i=2;i<n;i++) {
            d=tolower(a[i]); sub(/\.$/,"",d)
            if(domain_ok(d)) print "INSERT OR IGNORE INTO rules VALUES(" quote(d) "," action ");"
        }
    }
    close(path); metadata("policy_updated",now); print "COMMIT;"; fflush()
}
function identities(path, line,a,n,ip,mac,name) {
    commit(); print "BEGIN IMMEDIATE; DELETE FROM identities;"
    while((getline line < path)>0) {
        n=split(line,a,"|"); ip=a[1]; mac=tolower(a[2]); name=a[3]
        if(!ip_ok(ip) || !mac_ok(mac)) continue
        print "INSERT OR REPLACE INTO identities VALUES(" quote(ip) "," quote(mac) "," quote(name) "," now ");"
    }
    close(path); print "COMMIT;"; fflush()
}
function prune(k) {
    for(k in seen) if(now-seen[k]>30) forget(k)
    commit(); print "BEGIN IMMEDIATE;"
    print "DELETE FROM events WHERE timestamp < " now " - " retention_hours "*3600;"
    print "DELETE FROM events WHERE id < COALESCE((SELECT id FROM events ORDER BY id DESC LIMIT 1 OFFSET " (retention_rows-1) "),0);"
    metadata("heartbeat",now); print "COMMIT; PRAGMA wal_checkpoint(PASSIVE);"; fflush()
}
BEGIN {
    now=0; pending=0; last_prune=0; expected_pid=0; count=0
    print ".timeout 5000\nPRAGMA foreign_keys=ON; PRAGMA cache_size=-1024; PRAGMA synchronous=NORMAL; PRAGMA wal_autocheckpoint=256;"
    fflush()
}
$1=="__TICK__" { now=$2+0; for(k in seen) if(now-seen[k]>30) forget(k); commit(); if(now-last_prune>=60) {prune();last_prune=now}; next }
$1=="__PID__" { commit(); expected_pid=$2+0; next }
$1=="__POLICY__" { policy(substr($0,index($0," ")+1)); next }
$1=="__IDENTITIES__" { identities(substr($0,index($0," ")+1)); next }
{
    line=$0; epoch=now
    if(match(line,/\[[0-9]+\.[0-9]+\]/)) epoch=int(substr(line,RSTART+1,RLENGTH-2)+0)
    if(match(line,/dnsmasq-dhcp\[[0-9]+\]:/)) {
        tag=substr(line,RSTART,RLENGTH); pid=tag; gsub(/[^0-9]/,"",pid)
        if(pid+0!=expected_pid || !expected_pid) next
        message=substr(line,RSTART+RLENGTH); n=split(message,a,/[ \t]+/)
        # Leading whitespace makes the first split element empty.
        sub(/^[ \t]+/,"",message); n=split(message,a,/[ \t]+/)
        if(a[1] ~ /^DHCPACK\(/ && ip_ok(a[2]) && mac_ok(a[3])) {
            name=a[4]; if(name=="*" || name=="(null)") name=""
            begin_batch()
            print "INSERT OR REPLACE INTO identities VALUES(" quote(a[2]) "," quote(tolower(a[3])) "," quote(name) "," epoch ");"
            if(pending>=100) commit()
        }
        next
    }
    if(!match(line,/dnsmasq\[[0-9]+\]:/)) next
    tag=substr(line,RSTART,RLENGTH); pid=tag; gsub(/[^0-9]/,"",pid)
    if(pid+0!=expected_pid || !expected_pid) next
    message=substr(line,RSTART+RLENGTH); sub(/^[ \t]+/,"",message)
    n=split(message,a,/[ \t]+/); if(a[1] !~ /^[0-9]+$/) next
    client=tolower(a[2]); sub(/\/[0-9]+$/,"",client); if(!ip_ok(client)) next
    key=pid ":" a[1] ":" client
    if(a[3] ~ /^query\[/) {
        d=tolower(a[4]); sub(/\.$/,"",d); if(!domain_ok(d)) next
        type=a[3]; sub(/^query\[/,"",type); sub(/\]$/,"",type)
        if(type !~ /^[A-Z0-9]+$/) next
        if(!(key in seen) && count>=4096) next
        if(!(key in seen)) count++
        domains[key]=d; types[key]=type; times[key]=epoch; seen[key]=now
        next
    }
    # Upstream NXDOMAIN, cached negatives, SafeSearch and unmatched replies are not confirmed blocks.
    if(a[3]!="config" || a[5]!="is" || !(key in domains)) { if(a[3]=="reply" || a[3]=="cached") forget(key); next }
    d=tolower(a[4]); sub(/\.$/,"",d)
    if(d!=domains[key] || epoch-times[key]>30) next
    if(a[6]!="NXDOMAIN" && a[6]!="0.0.0.0" && a[6]!="::" && a[6]!="NODATA-IPv4" && a[6]!="NODATA-IPv6") next
    begin_batch()
    sql="WITH RECURSIVE suffix(domain) AS (VALUES(" quote(d) ") UNION ALL SELECT substr(domain,instr(domain,'.')+1) FROM suffix WHERE instr(domain,'.')>0), rule AS (SELECT r.domain,r.deny FROM rules r JOIN suffix s ON r.domain=s.domain ORDER BY length(r.domain) DESC,r.deny ASC LIMIT 1) "
    sql=sql "INSERT OR IGNORE INTO events(timestamp,client_ip,client_mac,device_name,domain,qtype,matched_rule,event_key) SELECT " times[key] "," quote(client) ",COALESCE(i.mac,''),COALESCE(i.name,'')," quote(d) "," quote(types[key]) ",rule.domain," quote(key ":" times[key] ":" d ":" types[key]) " FROM rule LEFT JOIN identities i ON i.ip=" quote(client) " AND i.updated_at<=" times[key] " WHERE rule.deny=1;"
    print sql
    forget(key)
    if(pending>=100) commit()
}
END { commit() }
