```
Usage: ubuu.sh -I "PATH[;PATH...]" -c FORMAT -o NAME [options]

Ultimate BackUp Utility in bash. Very simple but fast and reliable. And of course Open Source.
Creates a single compressed archive of the given paths, optionally encrypted if your openssl supports it.
The archive can be unpacked on any system with the same compression format.
The password is not stored anywhere, so make sure to remember it!



Mandatory:
  -I, --input PATHS        Paths to back up, separated by ';' (quote the whole value).
                           A trailing /* includes everything below (recursively).
                           Other wildcards (*, ?, [..]) are resolved too.
  -c, --compression FMT    tgz | zip | bzip | rar
  -o, --output NAME        Output file name (extension is added if missing)

Options:
  -C, --encrypt            Encrypt the backup (openssl enc -aes-256-cbc -salt).
                           You are asked for a password; ".enc" is appended to the file name.
  -d, --datetime           Append _YYYYmmdd_HHMMSS to the file name
  -s, --symlink-copy       Store symlinks as copies of what they point to
                           (default: store the symlinks themselves)
  -v, --verbose            Print progress while running
  -f, --force              Overwrite the output file if it already exists
  -p, --preview            List everything that would be archived, then exit
  -h, --help               Show this help

Source code: https://github.com/JensAndree/ubuu/
Version: 0.1.0

Examples:
  ubuu.sh -I "/etc/nginx;$HOME/My Documents/*" -c tgz -o /tmp/bk -d -v
  ubuu.sh -I "./src;./docs" -c zip -o backup -p
  ubuu.sh -I "./secrets" -c tgz -o vault -C
```
