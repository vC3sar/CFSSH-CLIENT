/// Dictionary of common sysadmin, devops, and server commands/tools for quick completion.
/// You can easily add more commands, subcommands, or flags to this list.
class CommandDictionary {
  CommandDictionary._();

  /// Default list of commands, tools, and frequent flags for tab-completion.
  static const List<String> defaultSuggestions = [
    // Web / SSL / Certs
    'letsencrypt',
    'certbot',
    'certbot --nginx',
    'certbot --apache',
    'certbot renew',
    'certbot certonly',
    'openssl',
    'nginx',
    'nginx -t',
    'nginx -s reload',
    'apache2',
    'apachectl',
    'caddy',
    'haproxy',

    // System & Services
    'systemctl',
    'systemctl status',
    'systemctl start',
    'systemctl stop',
    'systemctl restart',
    'systemctl reload',
    'systemctl enable',
    'systemctl disable',
    'journalctl',
    'journalctl -u',
    'journalctl -xe',
    'journalctl -f',
    'service',
    'crontab -e',
    'crontab -l',
    'shutdown -h now',
    'reboot',
    'uptime',
    'hostnamectl',

    // Package Managers
    'apt',
    'apt update',
    'apt upgrade',
    'apt install',
    'apt remove',
    'apt autoremove',
    'apt search',
    'apt-get',
    'apt-cache',
    'yum',
    'yum install',
    'yum update',
    'dnf',
    'dnf install',
    'dnf update',
    'pacman -Syu',
    'apk add',
    'apk update',

    // Containers & Orchestration
    'docker',
    'docker ps',
    'docker ps -a',
    'docker run',
    'docker stop',
    'docker restart',
    'docker logs',
    'docker logs -f',
    'docker exec -it',
    'docker images',
    'docker rmi',
    'docker volume',
    'docker network',
    'docker system prune',
    'docker compose',
    'docker compose up -d',
    'docker compose down',
    'docker compose logs -f',
    'docker compose ps',
    'docker-compose',
    'podman',
    'kubectl',
    'kubectl get pods',
    'kubectl get svc',
    'kubectl describe',
    'kubectl logs',

    // Networking & Connectivity
    'curl',
    'curl -I',
    'curl -fsSL',
    'wget',
    'ping',
    'traceroute',
    'netstat',
    'netstat -tulnp',
    'ss -tulnp',
    'ip addr',
    'ifconfig',
    'iptables',
    'iptables -L -n -v',
    'ufw',
    'ufw status',
    'ufw enable',
    'ufw allow',
    'ufw reload',
    'firewall-cmd',
    'nslookup',
    'dig',
    'tcpdump',
    'nmap',
    'ssh',
    'ssh-keygen',
    'ssh-copy-id',
    'rsync -avz',
    'scp',

    // File System & Disks
    'mkdir -p',
    'chmod +x',
    'chmod 600',
    'chmod 700',
    'chmod 755',
    'chown -R',
    'tar -czvf',
    'tar -xzvf',
    'unzip',
    'df -h',
    'du -sh',
    'du -h --max-depth=1',
    'lsblk',
    'fdisk -l',
    'mount',
    'umount',
    'find / -name',
    'grep -rnw',

    // Process & Resource Monitoring
    'htop',
    'btop',
    'top',
    'glances',
    'iotop',
    'iftop',
    'ps aux',
    'kill -9',
    'killall',
    'free -m',
    'free -h',
    'vmstat',
    'iostat',

    // Runtimes & Languages
    'git status',
    'git pull',
    'git push',
    'git checkout',
    'git commit -m',
    'git branch',
    'git log --oneline',
    'python3',
    'python3 -m venv',
    'pip install',
    'pip list',
    'node',
    'npm install',
    'npm run build',
    'pnpm install',
    'yarn',
    'pm2 list',
    'pm2 status',
    'pm2 logs',
    'pm2 restart',
    'pm2 save',

    // Databases
    'mysql -u root -p',
    'mysqldump',
    'mariadb',
    'psql -U postgres',
    'pg_dump',
    'redis-cli',
    'redis-server',
    'mongosh',
  ];

  /// Finds matching suggestions for a given input query/prefix.
  static List<String> findMatches(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final lower = trimmed.toLowerCase();

    // 1. Exact prefix matches on full suggestion
    final prefixMatches = <String>[];
    // 2. Exact prefix matches on the last word
    final wordPrefixMatches = <String>[];
    // 3. Substring contains matches
    final containsMatches = <String>[];

    for (final cmd in defaultSuggestions) {
      final cmdLower = cmd.toLowerCase();
      if (cmdLower == lower) continue; // Already typed full command

      if (cmdLower.startsWith(lower)) {
        prefixMatches.add(cmd);
      } else {
        // Check if any word starts with it
        final parts = cmdLower.split(' ');
        if (parts.any((p) => p.startsWith(lower))) {
          wordPrefixMatches.add(cmd);
        } else if (cmdLower.contains(lower)) {
          containsMatches.add(cmd);
        }
      }
    }

    final combined = <String>[
      ...prefixMatches,
      ...wordPrefixMatches,
      ...containsMatches,
    ];

    // Return unique top matches
    return combined.toSet().take(6).toList();
  }
}

