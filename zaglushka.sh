#!/bin/bash

# --- ЦВЕТА И ПЕРЕМЕННЫЕ ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 0. ДИСКЛЕЙМЕР И ПРОВЕРКИ ---
clear
echo -e "${RED}============================================================${NC}"
echo -e "${YELLOW}   🛡️  ULTIMATE SECURE SERVER SETUP (XRAY + NEXTCLOUD)  🛡️${NC}"
echo -e "${RED}============================================================${NC}"
echo -e "Скрипт выполнит следующие действия:"
echo -e "1. ${GREEN}Настроит Firewall:${NC} Закроет всё, кроме VPN и Web портов. Панель будет скрыта."
echo -e "2. ${GREEN}Создаст сайт:${NC} Маскировка под Nextcloud + Пасхалка (admin/admin)."
echo -e "3. ${GREEN}Установит панель:${NC} 3x-ui (MHSanaei)."
echo -e "4. ${GREEN}Выпустит SSL:${NC} Автоматически через Let's Encrypt."
echo -e "5. ${GREEN}Настроит Nginx:${NC} Разделение портов (80->HTTPS, 8080->Xray Fallback)."
echo -e ""
echo -e "${YELLOW}ТРЕБОВАНИЯ:${NC}"
echo -e "- Чистая система Ubuntu/Debian."
echo -e "- Домен, направленный на IP этого сервера."
echo -e "${RED}============================================================${NC}"
echo -e ""
read -p "Нажмите ENTER, чтобы начать..."

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Ошибка: Запустите скрипт от имени root!${NC}"
  exit
fi

# --- 1. СБОР ДАННЫХ ---
echo -e "\n${CYAN}--- [1/8] СБОР ДАННЫХ ---${NC}"
read -p "🌐 Введите ваш домен (например, example.com): " DOMAIN
if [ -z "$DOMAIN" ]; then echo -e "${RED}❌ Домен обязателен!${NC}"; exit; fi

read -p "📧 Email для сертификатов (например, admin@example.com): " EMAIL
if [ -z "$EMAIL" ]; then EMAIL="admin@$DOMAIN"; fi

read -p "🔢 Введите порт для панели 3x-ui (например, 2053): " PANEL_PORT
if [ -z "$PANEL_PORT" ]; then echo -e "${RED}❌ Порт обязателен!${NC}"; exit; fi

# --- 2. ОБНОВЛЕНИЕ СИСТЕМЫ ---
echo -e "\n${CYAN}--- [2/8] ОБНОВЛЕНИЕ СИСТЕМЫ ---${NC}"
apt update -q
apt install nginx ufw wget curl socat cron tar -y -q

# --- 3. НАСТРОЙКА FIREWALL (БЕЗОПАСНОСТЬ) ---
echo -e "\n${CYAN}--- [3/8] НАСТРОЙКА FIREWALL (UFW) ---${NC}"
# Если UFW не установлен - ставим
if ! command -v ufw &> /dev/null; then apt install ufw -y; fi

ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing

# Разрешаем порты
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP Redirect'
ufw allow 443/tcp comment 'Xray HTTPS'
ufw allow 8443/tcp comment 'Xray XHTTP'
ufw allow 8080/tcp comment 'Hidden Site Local' 
# ПОРТ ПАНЕЛИ НЕ ОТКРЫВАЕМ! (Security through obscurity)

echo "y" | ufw enable
echo -e "${GREEN}✅ Firewall настроен. Порт панели $PANEL_PORT закрыт снаружи (доступ только через туннель).${NC}"

# --- 4. ПОДГОТОВКА КОНТЕНТА САЙТА ---
echo -e "\n${CYAN}--- [4/8] СОЗДАНИЕ САЙТА-МАСКИРОВКИ ---${NC}"
WEB_DIR="/var/www/html"
rm -rf $WEB_DIR/*
mkdir -p $WEB_DIR

# Функция загрузки с проверкой
download_img() {
    local url=$1
    local dest=$2
    local name=$3
    echo -e "Загрузка $name..."
    if wget -q -O "$dest" "$url"; then
        # Проверка размера (защита от пустых файлов)
        fsize=$(stat -c%s "$dest")
        if [ "$fsize" -lt 1000 ]; then
            echo -e "${YELLOW}⚠️ Файл $name слишком маленький. Ссылка могла устареть.${NC}"
            read -p "Введите свою ссылку для $name: " new_url
            wget -q -O "$dest" "$new_url"
        else
            echo -e "${GREEN}OK${NC}"
        fi
    else
        echo -e "${RED}Ошибка загрузки $name!${NC}"
        read -p "Введите рабочую ссылку для $name: " new_url
        wget -q -O "$dest" "$new_url"
    fi
}

# Новые ссылки (Raw версии)
URL_LOGO="https://raw.githubusercontent.com/DenisSpirit/zaglushka/main/Logo.svg.png"
URL_MEME="https://raw.githubusercontent.com/DenisSpirit/zaglushka/main/Pic.jpg"

# Спрашиваем про кастомные ссылки
echo -e "${YELLOW}Хотите использовать стандартные картинки? [y/n]${NC}"
read -p "Ваш выбор: " USE_DEFAULT

if [ "$USE_DEFAULT" != "y" ]; then
    read -p "Ссылка на Логотип: " URL_LOGO
    read -p "Ссылка на Пасхалку: " URL_MEME
fi

download_img "$URL_LOGO" "$WEB_DIR/logo.png" "logo.png"
# Сохраняем мем как jpg, так как в источнике это jpg
download_img "$URL_MEME" "$WEB_DIR/secret_meme.jpg" "secret_meme.jpg"

# Генерация HTML
echo "Генерация index.html..."
cat << 'EOF' > "$WEB_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nextcloud</title>
    <link rel="icon" href="https://raw.githubusercontent.com/nextcloud/promo/master/nextcloud-icon.png">
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Oxygen-Sans, Ubuntu, Cantarell, "Helvetica Neue", sans-serif;
            background-color: #0082c9;
            background-image: url('https://raw.githubusercontent.com/nextcloud/server/master/core/img/background.jpg');
            background-position: center; background-size: cover; background-repeat: no-repeat;
            min-height: 100vh; width: 100%;
            display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 20px;
        }
        .login-box-container {
            background-color: rgba(255, 255, 255, 0.96);
            width: 100%; max-width: 350px;
            padding: 35px; border-radius: 12px;
            box-shadow: 0 15px 40px rgba(0,0,0,0.2);
            text-align: center; margin: auto; align-self: center;
            position: relative; z-index: 10; transition: opacity 0.5s ease;
        }
        .logo { margin-bottom: 30px; display: flex; justify-content: center; align-items: center; width: 100%; }
        .logo img { width: 200px; max-width: 100%; height: auto; object-fit: contain; display: block; }
        .input-group { margin-bottom: 15px; position: relative; width: 100%; }
        input {
            width: 100%; padding: 12px 40px 12px 12px; border: 1px solid #ccc; border-radius: 6px;
            font-size: 16px; color: #333; background: #fff; outline: none;
        }
        input:focus { border-color: #0082c9; box-shadow: 0 0 0 2px rgba(0, 130, 201, 0.2); }
        .input-icon {
            position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
            width: 18px; height: 18px; opacity: 0.5; pointer-events: none;
        }
        button {
            width: 100%; padding: 12px; background-color: #0082c9; color: white; border: none; border-radius: 6px;
            font-size: 16px; font-weight: 600; cursor: pointer; margin-top: 10px;
            display: flex; justify-content: center; align-items: center; transition: background 0.2s;
        }
        button:hover { background-color: #006aa3; }
        button:disabled { background-color: #ccc; cursor: default; }
        .links { margin-top: 20px; display: flex; flex-direction: column; gap: 10px; }
        .links a { color: #555; text-decoration: none; font-size: 14px; cursor: pointer; }
        .links a:hover { text-decoration: underline; color: #000; }
        .warning-box {
            background-color: #fff3cd; color: #5e4604; border: 1px solid #ffeeba; padding: 10px;
            border-radius: 5px; font-size: 14px; margin-bottom: 20px; text-align: left; display: none;
        }
        .footer {
            margin-top: 30px; font-size: 13px; color: rgba(255,255,255,0.8); text-align: center;
            z-index: 10; transition: opacity 0.5s ease;
        }
        .footer a { color: white; text-decoration: none; font-weight: bold; }
        
        #secret-overlay {
            position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
            z-index: 9999; display: none; opacity: 0; transition: opacity 1s ease-in;
            /* Исправлено расширение на .jpg */
            background-image: url('/secret_meme.jpg'), url('https://raw.githubusercontent.com/nextcloud/server/master/core/img/background.jpg');
            background-repeat: no-repeat, no-repeat;
            background-position: center center, center center;
            background-size: contain, cover;
        }
        .secret-text {
            position: absolute; bottom: 50px; left: 0; width: 100%; text-align: center;
            font-family: "Impact", "Arial Black", sans-serif;
            font-size: 60px; font-weight: bold; color: white; text-transform: uppercase;
            text-shadow: 2px 2px 0 #000, -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000;
            padding: 0 20px;
        }
        .hidden { display: none !important; }
        .spinner {
            display: none; width: 16px; height: 16px; border: 2px solid rgba(255,255,255,0.5);
            border-radius: 50%; border-top-color: #fff; animation: spin 0.8s linear infinite; margin-left: 8px;
        }
        @keyframes spin { to { transform: rotate(360deg); } }
    </style>
</head>
<body>
    <div class="login-box-container" id="main-container">
        <div class="logo"><img src="/logo.png" alt="Nextcloud"></div>
        <div id="login-view">
            <div id="login-error" class="warning-box">Wrong username or password.</div>
            <form id="login-form">
                <div class="input-group">
                    <input type="text" id="user" placeholder="Username or email" required>
                    <svg class="input-icon" viewBox="0 0 24 24" fill="#000"><path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"/></svg>
                </div>
                <div class="input-group">
                    <input type="password" id="pass" placeholder="Password" required>
                    <svg class="input-icon" viewBox="0 0 24 24" fill="#000"><path d="M21 10h-8.35C11.83 7.67 9.61 6 7 6c-3.31 0-6 2.69-6 6s2.69 6 6 6c2.61 0 4.83-1.67 5.65-4H13l2 2 2-2 2 2 4-4.04L21 10zM7 15c-1.65 0-3-1.35-3-3s1.35-3 3-3 3 1.35 3 3-1.35 3-3 3z"/></svg>
                </div>
                <button type="submit" id="login-btn">Log in <div class="spinner"></div></button>
            </form>
            <div class="links"><a onclick="toggleView('device')">Log in with device</a><a onclick="toggleView('forgot')">Forgot password?</a></div>
        </div>
        <div id="device-view" class="hidden">
            <div style="margin-bottom: 20px; font-weight: 600; color: #444;">Device Login</div>
            <div id="device-msg" class="warning-box">Connection failed.</div>
            <form id="device-form"><div class="input-group"><input type="text" placeholder="Account name" required></div><button type="submit" id="device-btn">Confirm <div class="spinner"></div></button></form>
            <div class="links"><a onclick="toggleView('login')">Back to login</a></div>
        </div>
        <div id="forgot-view" class="hidden">
            <div style="margin-bottom: 20px; font-weight: 600; color: #444;">Reset Password</div>
            <div id="reset-msg" class="warning-box" style="background:#e6f7e6;color:#2e7d32;border-color:#c8e6c9;">Link sent.</div>
            <form id="forgot-form"><div class="input-group"><input type="text" id="reset-user" placeholder="Email" required></div><button type="submit" id="reset-btn">Reset <div class="spinner"></div></button></form>
            <div class="links"><a onclick="toggleView('login')">Back to login</a></div>
        </div>
    </div>
    <div class="footer" id="main-footer"><a href="https://nextcloud.com" target="_blank">Nextcloud</a> – a safe home for all your data</div>
    <div id="secret-overlay"><div class="secret-text">Ебать ты молодец!!!!</div></div>
<script>
    function toggleView(view) {
        const views = ['login-view', 'forgot-view', 'device-view'];
        document.querySelectorAll('.warning-box').forEach(el => el.style.display = 'none'); document.querySelectorAll('form').forEach(f => f.reset());
        views.forEach(v => { const el = document.getElementById(v); if (v.startsWith(view)) el.classList.remove('hidden'); else el.classList.add('hidden'); });
    }
    document.getElementById('login-form').addEventListener('submit', function(e) {
        e.preventDefault();
        const btn = document.getElementById('login-btn'); const spin = btn.querySelector('.spinner'); const err = document.getElementById('login-error');
        const user = document.getElementById('user').value; const pass = document.getElementById('pass').value;
        btn.disabled = true; spin.style.display = 'inline-block'; err.style.display = 'none';
        if (user === 'admin' && pass === 'admin') { setTimeout(() => { document.getElementById('main-container').style.opacity = '0'; document.getElementById('main-footer').style.opacity = '0'; const overlay = document.getElementById('secret-overlay'); overlay.style.display = 'block'; setTimeout(() => { overlay.style.opacity = '1'; }, 50); }, 1000); return; }
        setTimeout(() => { btn.disabled = false; spin.style.display = 'none'; err.style.display = 'block'; document.getElementById('pass').value = ''; }, 1500);
    });
    document.getElementById('device-form').addEventListener('submit', function(e) { e.preventDefault(); const btn = document.getElementById('device-btn'); const spin = btn.querySelector('.spinner'); const msg = document.getElementById('device-msg'); btn.disabled = true; spin.style.display = 'inline-block'; msg.style.display = 'none'; setTimeout(() => { btn.disabled = false; spin.style.display = 'none'; msg.style.display = 'block'; }, 1000); });
    document.getElementById('forgot-form').addEventListener('submit', function(e) { e.preventDefault(); const btn = document.getElementById('reset-btn'); const spin = btn.querySelector('.spinner'); const msg = document.getElementById('reset-msg'); btn.disabled = true; spin.style.display = 'inline-block'; setTimeout(() => { btn.disabled = false; spin.style.display = 'none'; msg.style.display = 'block'; document.getElementById('reset-user').value = ''; }, 1000); });
</script>
</body>
</html>
EOF

# --- 5. УСТАНОВКА И ПРОВЕРКА ПАНЕЛИ ---
echo -e "\n${CYAN}--- [5/8] ПРОВЕРКА ПАНЕЛИ 3X-UI ---${NC}"
if ! command -v x-ui &> /dev/null; then
    echo -e "${YELLOW}Панель не найдена. Запускаем установку...${NC}"
    echo -e "${YELLOW}⚠️ ВАЖНО: Когда скрипт спросит порт - введите: $PANEL_PORT ${NC}"
    echo -e "Нажмите Enter для старта установки панели..."
    read
    bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
else
    echo -e "${GREEN}Панель уже установлена.${NC}"
fi

# --- 6. ПОЛУЧЕНИЕ СЕРТИФИКАТОВ ---
echo -e "\n${CYAN}--- [6/8] ВЫПУСК SSL СЕРТИФИКАТОВ ---${NC}"
# Установка acme.sh
curl https://get.acme.sh | sh -s email=$EMAIL > /dev/null
source ~/.bashrc

# Временная остановка Nginx (освобождаем порт 80)
systemctl stop nginx

# Попытка выпуска
echo "Выпуск сертификата для $DOMAIN..."
~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force

# Создание папки и копирование
mkdir -p /etc/x-ui/server_certs
~/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
--key-file       /etc/x-ui/server_certs/private.key  \
--fullchain-file /etc/x-ui/server_certs/public.crt

chmod 644 /etc/x-ui/server_certs/*

# Запуск Nginx обратно
systemctl start nginx

if [ -f "/etc/x-ui/server_certs/public.crt" ]; then
    echo -e "${GREEN}✅ Сертификаты успешно получены и скопированы.${NC}"
else
    echo -e "${RED}❌ Ошибка получения сертификатов! Проверьте домен и DNS.${NC}"
fi

# --- 7. КОНФИГУРАЦИЯ NGINX (SPLIT) ---
echo -e "\n${CYAN}--- [7/8] ФИНАЛЬНАЯ НАСТРОЙКА NGINX ---${NC}"
cat << EOF > /etc/nginx/sites-enabled/default
# 1. ПУБЛИЧНЫЙ ПОРТ 80 (Редирект на HTTPS)
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

# 2. СКРЫТЫЙ ПОРТ 8080 (Для Xray Fallback)
server {
    listen 127.0.0.1:8080;
    server_name $DOMAIN;
    root $WEB_DIR;
    index index.html;

    server_tokens off;
    
    # Маскировка заголовков под Nextcloud
    add_header Set-Cookie "nc_sameSiteCookielax=true; path=/; httponly;secure; samesite=lax";
    add_header Set-Cookie "nc_sameSiteCookiestrict=true; path=/; httponly;secure; samesite=strict";
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Robots-Tag "none" always;
    add_header X-Download-Options "noopen" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;

    error_page 403 /index.html;
    error_page 404 /index.html;
    error_page 500 /index.html;
    location / { try_files \$uri \$uri/ =404; }
    
    # Фейковый status.php
    location = /status.php {
        return 200 '{"installed":true,"maintenance":false,"needsDbUpgrade":false,"version":"27.0.2.1","versionstring":"27.0.2","edition":"","productname":"Nextcloud"}';
        add_header Content-Type application/json;
    }
}
EOF

# Проверка конфига и рестарт
nginx -t
systemctl restart nginx

# --- 8. ИТОГОВАЯ ИНСТРУКЦИЯ ---
IP=$(curl -s ifconfig.me)
echo -e ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   ✅  НАСТРОЙКА ЗАВЕРШЕНА!  ✅${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e ""
echo -e "${RED}⚠️ ВНИМАНИЕ: Порт панели $PANEL_PORT закрыт Файрволом!${NC}"
echo -e "Вы не сможете зайти по http://$IP:$PANEL_PORT"
echo -e ""
echo -e "${YELLOW}👉 КАК ЗАЙТИ В ПАНЕЛЬ:${NC}"
echo -e "1. На своем ПК откройте терминал (PowerShell/CMD/Terminal)."
echo -e "2. Введите команду для SSH-туннеля:"
echo -e "   ${CYAN}ssh -L $PANEL_PORT:127.0.0.1:$PANEL_PORT root@$IP${NC}"
echo -e "3. Не закрывайте окно терминала."
echo -e "4. В браузере откройте: ${CYAN}http://localhost:$PANEL_PORT${NC}"
echo -e ""
echo -e "${YELLOW}👉 ЧТО ПРОПИСАТЬ В НАСТРОЙКАХ XRAY (INBOUND):${NC}"
echo -e "----------------------------------------------------"
echo -e "Remark:         ${GREEN}VLESS-Vision${NC}"
echo -e "Protocol:       ${GREEN}vless${NC}"
echo -e "Port:           ${GREEN}443${NC} (Обязательно!)"
echo -e "Transmission:   ${GREEN}TCP${NC}"
echo -e "Flow:           ${GREEN}xtls-rprx-vision${NC}"
echo -e "TLS:            ${GREEN}Enabled${NC}"
echo -e "  -> Domain:    ${GREEN}$DOMAIN${NC}"
echo -e "  -> Public:    ${GREEN}/etc/x-ui/server_certs/public.crt${NC}"
echo -e "  -> Private:   ${GREEN}/etc/x-ui/server_certs/private.key${NC}"
echo -e "Sniffing:       ${GREEN}Enabled${NC}"
echo -e "FALLBACKS (ВАЖНО!):"
echo -e "  -> Dest:      ${GREEN}8080${NC}"
echo -e "  -> Xver:      ${GREEN}0${NC}"
echo -e "----------------------------------------------------"
echo -e ""
echo -e "Проверка сайта: https://$DOMAIN (Попробуйте admin/admin)"
echo -e "Удачи! 🚀"
