
# >>> JVM installed by coursier >>>
export JAVA_HOME="/home/kannar/.cache/coursier/arc/https/github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.8%252B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.8_9.tar.gz/jdk-21.0.8+9"
export PATH="$PATH:/home/kannar/.cache/coursier/arc/https/github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.8%252B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.8_9.tar.gz/jdk-21.0.8+9/bin"
# <<< JVM installed by coursier <<<

# >>> coursier install directory >>>
export PATH="$PATH:/home/kannar/.local/share/coursier/bin"
# <<< coursier install directory <<<
#
export MOZ_ENABLE_WAYLAND=1

# Secrets (API tokens, etc.) live outside any repo.
[ -f ~/.local/share/secrets.env ] && . ~/.local/share/secrets.env
