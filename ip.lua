-- Информация об astra https://cesbo.com/ru/astra/
-- Информация о ForkPlayer http://forkplayer.tv/
-- Этот файл кидать в /etc/astra/mod/
-- Работа с модом
-- Включить в web панели astra в Settings / Http play Allow HTTP access to all streams
-- Получить все каналы http://ip:port/playlist.m3u8 
-- Для получения каналов с определенной Groups /playlist.m3u8?category=<Category Name>  
-- Запускайте astra с ключем --log /var/log/astra.log для записи этим модом логов (ip, mac, referer) доступа к листу
-- Разрешить доступ со всех мест access_referer = {"*"}
access_referer = {
    "http://mylist.obovse.ru/forkiptv",
    "http://mylist.obovse.ru/iptv",
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
	
	local initial = request.query.initial
	if not initial then
		initial="empty"
	end
	local referer = request.headers["save-data"] or request.headers["Save-Data"]
	if not referer then
		referer="empty"
	end
	
	local mac = request.query.box_mac
	if not mac then
		mac="empty"
	end
	local category = request.query.category
	if not category then
		category="all"
	end
	local token = (request.addr..os.date("%m%d")):md5():hex():lower()
	
	local a = request.query.server
	
    if not a then
        a = request.headers["host"]
        if not a then
            server:abort(client, 400, "Server address is not defined")
            return nil
        end 
    end
	
	if not valid("*",access_referer) and not valid(referer,access_referer) then
		log.error("ABORT GETLIST category:" .. category .. " ip:" .. request.addr .." NEED ADD referer:" .. referer .." mac:"..mac.." initial:"..initial)
		server:send(client, {
			code = 200,
			headers = { "Access-Control-Allow-Origin: *","Content-Type: text/html", "Connection: close" },
			content = "#EXTM3U\r\n#EXTINF:-1,Abort access from:" .. referer.."\r\nhttp://null\r\n",
		})
        return nil
	end
	
	log.info("GETLIST category:" .. category .. " ip:" .. request.addr .." referer:" .. referer .." mac:"..mac.." initial:"..initial) 
	
	
    local p = "#EXTM3U\r\n"
    if http_play_hls then
        for k,c in pairs(channel_list_ID) do
            if c.config.enable ~= false then
                p = p .. "#EXTINF:-1," .. c.config.name .. "\r\nhttp://" .. a .. "/play/" .. k .. "/index.m3u8?token=" .. token .. "&box_mac="..mac.."&initial="..urlencode(initial).."\r\n"
            end
        end
    elseif http_play_stream then
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
					p = p .. "#EXTINF:-1," .. c.config.name .. "\r\nhttp://" .. a .. "/play/" .. k .. "?token=" .. token .. "&box_mac="..mac.."&initial="..urlencode(initial).."\r\n"
				end
            end
        end
    else
        server:abort(client, 404)
        return nil
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

function auth_request(client_id, request, callback)
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
	local token = (request.addr..os.date("%m%d")):md5():hex():lower()
	if request.query.token==token then
		result = true		
	    log.info("channel:" .. stat.channel_name .. " client:" .. stat.request.addr .." mac:"..mac.." initial:"..initial.. "  uptime:" .. uptime .. "min.")    
	else
		log.error("NOT valid token channel:" .. stat.channel_name .. " client:" .. stat.request.addr .." mac:"..mac.." initial:"..initial.. " uptime:" .. uptime .. "min.") 
	end
	
	callback(result)
    
end

control_server_instance:remove("/playlist.m3u8")
control_server_instance:insert("/playlist.m3u8", custom_playlist_m3u8)
