-- Информация об astra https://cesbo.com/ru/astra/
-- Информация о ForkPlayer http://forkplayer.tv/
-- Этот файл кидать в /etc/astra/mod/
-- Работа с модом
-- Включить в web панели astra в Settings / Http play Allow HTTP access to all streams

-- Ссылку вставить в плеер или здесь http://forkplayer.tv/mylist/ Добавить ссылку на внешний самообновляемый плейлист  
-- Ссылка на все каналы http://ip:port/playlist.m3u8 
-- Для получения каналов с определенной Groups http://ip:port/playlist.m3u8?category=<Category Name>  

-- Запускайте astra с ключем --log /var/log/astra.log для записи этим модом логов (ip, mac, referer) доступа к листу
-- Разрешить доступ со всех мест access_referer = {"*"}
access_referer = {
    "http://mylist.obovse.ru/forkiptv",
    "http://mylist.obovse.ru/iptv",
}

-- Блокировка мак адресов, empty - вход без мак адреса, например с другого виджета. Не действует на вход по логину:паролю
blocked_mac={
	"empty",
}
function valid(data, array)
	local u = { }
	for _, v in ipairs(array) do u[v] = true end
	 return u[data]
  
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

local function urlencode(url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "%%20")
  return url
end

local hex_to_char = function(x)
  return string.char(tonumber(x, 16))
end

local urldecode = function(url)
  if url == nil then
    return
  end
  url = url:gsub("%%20", " ")
  url = url:gsub("%%(%x%x)", hex_to_char)
  return url
end
 
function custom_playlist_m3u8(server, client, request)
    if not request then
        return nil
    end
	
	
	local referer = request.headers["save-data"] or request.headers["accept"]
	if not referer then
		referer=""
	end
	local xi=string.find(referer,"http")
	if not referer then
		referer="empty"
	elseif xi == nil then
		xi = -1
		referer="not"	
	end
	local q = ""
	local auth = request.query.auth
	if auth then
		q="&auth="..auth
	end
	local ip=request.addr
	local initial = request.query.initial
	if not initial then
		initial="empty"
	end
	local mac = request.query.box_mac
	if not mac then
		mac="empty"
	end
	local category = request.query.category
	if not category then
		category="all"
	end
	local token = (initial..ip..os.date("%m%W")..mac):md5():hex():lower()
	
	local a = request.query.server
	
    if not a then
        a = request.headers["host"]
        if not a then
            server:abort(client, 400, "Server address is not defined")
            return nil
        end 
    end
	
	if not valid("*",access_referer) and not valid(referer,access_referer) and not auth then
		log.error("ABORT GETLIST category:" .. category .. " ip:" .. ip .." NEED ADD referer:" .. referer .." mac:"..mac.." initial:"..initial)
		server:send(client, {
			code = 200,
			headers = { "Access-Control-Allow-Origin: *","Content-Type: text/html", "Connection: close" },
			content = "#EXTM3U\r\n#EXTINF:-1,Abort access from:" .. referer.."\r\nhttp://null\r\n",
		})
        return nil
	end
	
	log.info("GETLIST category:" .. category .. " ip:" .. ip .." referer:" .. referer .." mac:"..mac.." initial:"..initial) 
	
	local h = ""
    if config_data and config_data.settings and config_data.settings.http_play_hls then
        h = "/index.m3u8"
    end
	
	
	local x = {}
	for k,c in pairs(channel_list_ID) do
		if c.config.enable ~= false then
			local add=false
			if category=="all" then 
				add=true
			else
				if not c.config.groups then
					
				else
					if not c.config.groups[""..category] then 
						
					else
						add=true							
					end
				end
			end
			if add then			
				table.insert(x, {
				name = c.config.name,
				link = "http://" .. a .. "/play/" .. k ..h.. "?token=" .. token .. "&box_mac="..mac.."&initial="..urlencode(initial)..q,
			})
			end
		end
	end
	
	table.sort(x, function(a, b)
        return a.name < b.name
    end)
	
    local p = "#EXTM3U\r\n"
	for _,c in ipairs(x) do
        p = p .. "#EXTINF:-1," .. c.name .. "\r\n" .. c.link .. "\r\n"
    end
	
	if p == "#EXTM3U\r\n" then 
	p = p .. "#EXTINF:-1,Нет каналов в категории " .. category .. "\r\nhttp://\r\n"
	end
    server:send(client, {
        code = 200,
        headers = { "Access-Control-Allow-Origin: *","Content-Type: application/x-mpegurl", "Connection: close" },
        content = p,
    })
end

function auth_request2(client_id, request, callback)
    if not request then
        return nil
    end
	local stat = http_output_client_list[client_id]
	local uptime = math.floor((os.time() - stat.st) / 60)
	local result = false
	local mac = request.query.box_mac
	local initial = request.query.initial
	if not initial then
		initial="empty"
	else		
		initial=urldecode(initial)
	end
	if not mac then
		mac="empty"
	end
	local token = (initial..request.addr..os.date("%m%W")..mac):md5():hex():lower()
	if request.query.auth then		
	
	elseif valid(mac,blocked_mac) then
		log.error("Blocked mac channel:" .. stat.channel_name .. " client:" .. stat.request.addr .." mac:"..mac.." initial:"..initial.. " uptime:" .. uptime .. "min.") 
	elseif request.query.token==token then
		result = true		
	    log.info("channel:" .. stat.channel_name .. " client:" .. stat.request.addr .." mac:"..mac.." initial:"..initial.. "  uptime:" .. uptime .. "min.")    
	else
		log.error("NOT valid token channel:" .. stat.channel_name .. " client:" .. stat.request.addr .." mac:"..mac.." initial:"..initial.. " uptime:" .. uptime .. "min.") 
	end
	if not result and config_data.auth_options and config_data.auth_options.promo then
            -- Переадресация на промо-канал
		callback(config_data.auth_options.promo)
	else
		callback(result)
	end
    
end


-- Дополнительные параметры пользователей --
astra_storage["/mod.js"] = astra_storage["/mod.js"] .. [[
(function() {
"use strict";

var value2date = function(v) {
    if(!v) return "";
    var d = new Date(v * 1000);
    var dd = ("0" + d.getDate()).slice(-2);
    var dm = ("0" + (d.getMonth() + 1)).slice(-2);
    var dy = d.getFullYear();
    return dd + "." + dm + "." + dy;
};

SettingsUsersModule.modules.push({
    // Элементы для формы свойств пользователей
    renderSettings: function(form) {
        // Ограничение доступа по IP
        form.input("IP", "user.ip");

        // Ограничение доступа по дате
        var d = form.scope.get("user.date");
        if(d) form.scope.set("$user-date", value2date(d));
        form.input("Date", "$user-date", "Format: DD.MM.YYYY")
            .on("input", function() {
                var x = this.value || "0";
                x = x.split(".");
                if(x.length != 3) {
                    x = 0;
                } else {
                    x = new Date(Number(x[2]), Number(x[1]) - 1, Number(x[0]));
                    x = x.getTime() / 1000;
                }
                form.scope.set("user.date", x);
            });

        // Ограничение количества одновременных подключений
        form.input("Limit connections", "user.conlimit", "Default: 0 - unlimited");

        // Пакеты каналов
    var categoriesMap = [{ value: "" }];
    $.forEach(app.hosts[location.host].config.categories, function(x) {
        categoriesMap.push({ value: x.name });
    });
    categoriesMap.sort(function(a,b) { return a.value.localeCompare(b.value) });

        var packages = form.scope.get("user.packages");
        form.header("Packages", "New Package", function() {
            if(!packages) { packages = []; form.scope.set("user.packages", packages) }
            packages.push("");
            form.scope.reset()
        });
        $.forEach(packages, function(v, k) {
            form.choice("", "user.packages." + k, categoriesMap)
                .on("change", function() {
                    if(!this.value) {
                        packages.splice(k, 1);
                        if(!packages.length) form.scope.set("user.packages");
                        form.scope.reset();
                    }
                });
        });
    },
    // Элементы для заголовка таблицы общего списка пользователей
    renderHeader: function(row) {
        var o = function(a, b) {
            var ca = Number(a.dataset.value);
            var cb = Number(b.dataset.value);
            return (ca == cb) ? 0 : ((ca > cb) ? 1 : -1);
        };

        row.addChild($.element("th")
            .setText("IP")
            .setStyle("width", "150px")
            .addAttr("data-order", "on")
            .dataOrder(o));

        row.addChild($.element("th")
            .setText("Date")
            .setStyle("width", "150px")
            .addAttr("data-order", "on")
            .dataOrder(o));
    },
    // Элементы для строк общего списка пользователей
    renderItem: function(row, user) {
        row.addChild($.element("td")
            .addAttr("data-value", ip2num(user.ip))
            .setText(user.ip));

        row.addChild($.element("td")
            .addAttr("data-value", user.date)
            .setText(value2date(user.date)));
    }
});

})();
]]

-- Дополнительные параметры авторизации --
astra_storage["/mod.js"] = astra_storage["/mod.js"] .. [[
(function() {
"use strict";

// Представление модуля в меню Settings
var SettingsAuthOptionsModule = {
    label: "HTTP Authentication Options",
    link: "#/settings-http-auth-options",
    order: 9,
};

// Приём и обработка изменённых параметров
SettingsAuthOptionsModule.run = function() {
    app.scope.on("set-http-auth-options", function(event) {
        var hostId = event.host,
            data = event.data,
            appHost = app.hosts[hostId];

        if(data.auth_options) appHost.config.auth_options = data.auth_options;
        else delete(appHost.config.auth_options);

        $.msg({ title: "HTTP Authentication Options saved" });
    });
};

// Форма с параметрами
SettingsAuthOptionsModule.render = function(object) {
    var self = this,
        appHost = app.hosts[location.host],
        form = new Form(self.scope, object);

    var categoriesMap = [{ value: "" }];
    $.forEach(appHost.config.categories, function(x) {
        categoriesMap.push({ value: x.name });
    });
    categoriesMap.sort(function(a,b) { return a.value.localeCompare(b.value) });

    form.input("Promo Channel", "promo");
    form.choice("FTA Category", "fta", categoriesMap);

    var serialize = function() {
        var data = self.scope.serialize();

        $.forEach(data, function(v, k) {
            if(!v) delete(data[k]);
        });

        return data;
    }

    var btnApply = $.element.button("Apply")
        .addClass("submit")
        .on("click", function() {
            appHost.request({
                cmd: "set-http-auth-options",
                auth_options: serialize(),
            }, function(data) {
                //
            }, function() {
                $.err({ title: "Failed to save settings" });
            });
        });

    form.submit().addChild(btnApply);
};

// Запуск модуля
SettingsAuthOptionsModule.init = function() {
    if($.body.scope) $.body.scope.destroy();

    var appHost = app.hosts[location.host],
        scope = (appHost.config.auth_options != undefined) ? $.clone(appHost.config.auth_options) : {};

    window.renderContent = SettingsAuthOptionsModule.render;

    $.body
        .bindScope(scope)
        .on("destroy", function() {
            delete(window.renderContent);
        });
};

// Регистрация модуля
app.modules.push(SettingsAuthOptionsModule);
app.settings.push(SettingsAuthOptionsModule);

})();
]]

-- API метод для сохранения дополнительных параметров авторизации --
control_api["set-http-auth-options"] = function(server, client, request)
    config_data.auth_options = request.auth_options

    if #_control_clients ~= 0 then
        control_clients_send({
            scope = "set-http-auth-options",
            auth_options = request.auth_options,
        })
    end

    if config_path then json.save(config_path, config_data) end
    control_api_response(server, client, { ["set-http-auth-options"] = "ok" })
end

-- Авторизация --
local conlimitList = {}
function auth_request(client_id, request, callback)
    local session_data = http_output_client_list[client_id]

    -- Завершение подключения
    if not request then
        if session_data.login then
            local conlimit = conlimitList[session_data.login]
            if conlimit then
                for k,v in ipairs(conlimit) do
                    if v == client_id then
                        table.remove(conlimit, k)
                        break
                    end
                end
                if #conlimit == 0 then
                    conlimitList[session_data.login] = nil
                end
            end
        end
        return nil
    end

    local function check_access()
        local groups = session_data.channel_data.config.groups

        if config_data.auth_options then
            -- Каналы без авторизации (FTA Category)
            local fta_group = config_data.auth_options.fta
            if fta_group and groups and groups[fta_group] then
                print(fta_group)
                table.dump(groups)
                return true
            end
        end

        -- Авторизация пользователя по логину и паролю
        if not request.query.auth then
            return false
        end
        local b = request.query.auth:find(":")
        if not b then
            return false
        end
        local pass = request.query.auth:sub(b + 1)
        local login = request.query.auth:sub(1, b - 1)

        -- Проверка логина и пароля
        local user = check_cipher(login, pass)
        if not user then
            return false
        end

        -- Проверка IP адреса
        if user.ip ~= nil and user.ip ~= request.addr then
            return false
        end

		local initial = request.query.initial
		if not initial then
			initial="empty"
		end
		local mac = request.query.box_mac
		if not mac then
			mac="empty"
		end		
        -- Проверка даты
        if user.date ~= nil and user.date < os.time() then
			log.error("end date user:" .. login .. " client:" .. request.addr .." mac:"..mac.." initial:"..initial) 
            return false
        end
		
		local token = (initial..request.addr..os.date("%m%W")..mac):md5():hex():lower()
		if request.query.token~=token then
			log.error("error token user:" .. login .. " client:" .. request.addr .." mac:"..mac.." initial:"..initial) 
			return false
		end
        -- Проверка пакетов
        if user.packages then
            local function checkPackages()
                if groups then
                    for _,x in ipairs(user.packages) do
                        if groups[x] then
                            return true
                        end
                    end
                end
                return false
            end
            if not checkPackages() then
                return false
            end
        end

        -- Проверка одновременных подключений
        if user.conlimit ~= nil and tonumber(user.conlimit) ~= 0 then
            local conlimit = conlimitList[login]
            if not conlimit then
                conlimit = {}
                conlimitList[login] = conlimit
            end
            table.insert(conlimit, client_id)
            -- Если подклчений больше лимита закрыть первое подключение
            if #conlimit > tonumber(user.conlimit) then
                local first_client_id = conlimit[1]
                local first_session_data = http_output_client_list[first_client_id]
                first_session_data.server:close(first_session_data.client)
            end
        end

        -- Сохранить логин пользователя в сессиях
        session_data.login = login

        return true
    end

    if check_access() then
        -- Разрешить доступ
        callback(true)
    else
       auth_request2(client_id, request, callback)       
    end
end


control_server_instance:remove("/playlist.m3u8")
control_server_instance:insert("/playlist.m3u8", custom_playlist_m3u8)
