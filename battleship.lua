-- Если нас подключили не из Си, выходим
if msleep == nil then
	os.exit()
end

--[[ Добавил энтропии, иначе при частых запусках значения,
получаемые через генератор, сильно повторяются ]]
local seed = string.byte(io.open("/dev/random", "rb"):read(1))
math.randomseed(os.time() + seed)

function sign(x)
	return x > 0 and 1 or x < 0 and -1 or 0
end

-- Работа с кодами Морзе
morse = {
	-- Длительность точки (от неё отталкиваются остальные задержки)
	delay = 200,

	table = {
		["А"]="._",
		["Б"]="_...",
		["В"]=".__",
		["Г"]="__.",
		["Д"]="_..",
		["Е"]=".",
		["Ё"]=".",
		["Ж"]="..._",
		["З"]="__..",
		["И"]="..",
		["Й"]=".___",
		["К"]="_._",
		["Л"]="._..",
		["М"]="__",
		["Н"]="_.",
		["О"]="___",
		["П"]=".__.",
		["Р"]="._.",
		["С"]="...",
		["Т"]="_",
		["У"]=".._",
		["Ф"]=".._.",
		["Х"]="....",
		["Ц"]="_._.",
		["Ч"]="___.",
		["Ш"]="____",
		["Щ"]="__._",
		["Ъ"]="__.__",
		["Ы"]="_.__",
		["Ь"]="_.._",
		["Э"]=".._..",
		["Ю"]="..__",
		["Я"]="._._",
		["."]="......",
		[","]="._._._",
		["?"]="..__..",
		["!"]="__..__",
		["1"]=".____",
		["2"]="..___",
		["3"]="...__",
		["4"]="...._",
		["5"]=".....",
		["6"]="_....",
		["7"]="__...",
		["8"]="___..",
		["9"]="____.",
		["0"]="_____",
	}
}

-- Вывод одного символа
function morse:char(ch)
	local table = self.table[ch]

	for i = 1, #table do
		local s = table:sub(i, i)

		led_on(true)
		-- Тире — как три точки
		msleep(self.delay * (s == "_" and 3 or 1))
		led_on(false)

		-- Пауза между символами, если символ не последний
		if i ~= #table then
			msleep(self.delay)
		end
	end
end

-- Вывод слов
function morse:words(str)
	-- Признак конца предложения (чтобы не было паузы в конце)
	local EOF = utf8.char(26)

	for ch in (str..EOF):gmatch(utf8.charpattern) do
		if ch == " " then
			-- Пауза между словами
			msleep(7 * self.delay)
		elseif ch ~= EOF then
			self:char(ch)
			-- Пауза между символами
			msleep(3 * self.delay)
		end
	end
end

-- Поле боя
field = {
	-- Порядковый номер выводимого корабля
	num = 1,

	field = {
		["А"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["Б"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["В"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["Г"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["Д"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["Е"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["Ж"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["З"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["И"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		["К"] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
	},
}

-- Конструктор
function field.new()
	return setmetatable({}, field)
end

-- Вывод поля боя (для отладки)
function field:debug()
	local keys = {}

	for k in pairs(self.field) do
		table.insert(keys, k)
	end

	table.sort(keys)

	print('    '..table.concat(keys, ' '))

	for y = 1, 10 do
		io.write(string.format("%02s", y)..': ')

		for _, x in ipairs(keys) do
			local v = self.field[x][y]
			io.write((v == nil and '_' or v)..' ')
		end
		print()
	end
end

-- Перевод цифры в букву, 1 → А, 2 → Б,…
function field:_d2l(d)
	local l = utf8.char(1039 + d)
	return l == 'Й' and 'К' or l
end

-- Итератор для вертикального и горизонтальных кораблей
function field:ship_iter(x, y, l, is_vert)
	local _L = {x = x, y = y}
	local var = is_vert and 'y' or 'x'
	local max = _L[var] + l - 1

	_L[var] = _L[var] - 1

	return function()
		if _L[var] < max then
			_L[var] = _L[var] + 1
			return _L.x, _L.y
		end
	end
end

-- Получение всех точек вокруг, включая её саму
function field:flap_around(x, y)
	local minx, maxx = math.max(1, x - 1), math.min(10, x + 1)
	local miny, maxy = math.max(1, y - 1), math.min(10, y + 1)

	x, y = minx, miny

	return function()
		if x <= maxx and y <= maxy then
			x = x + 1
			return x - 1, y
		else
			if y <= maxy then
				x, y = minx, y + 1
				return x, y - 1
			end
		end
	end
end

-- Бросаем фигуру на поле
function field:drop_ship(l)
	local is_vert, x, y = math.random() > .5

	repeat
		x = math.random(10 - (is_vert and 0 or l))
		y = math.random(10 - (is_vert and l or 0))
	until field:check_ship(x, y, l, is_vert)

	--[[ Идея простая: кидаем корабль на поле и
	потихоньку начинаем его смещать в произвольную строну,
	пока не наткнёмся на препятствие ]]
	local nx, ny

	if is_vert then
		ny = math.random(10 - l)
		nx = ({1, 10})[math.random(2)]
	else
		ny = ({1, 10})[math.random(2)]
		nx = math.random(10 - l)
	end

	while nx ~= x or ny ~= y do
		local dx = sign(nx - x)
		local dy = sign(ny - y)

		if not field:check_ship(x + dx, y + dy, l, is_vert) then
			break
		end

		x, y = x + dx, y + dy
	end

	return x, y, is_vert
end

-- Заполнение поля
function field:fill()
	local x, y, is_vert = field:drop_ship(4)

	field:set_ship(x, y, 4, is_vert)

	local x, y, is_vert = field:drop_ship(3)

	field:set_ship(x, y, 4, is_vert)

	local x, y, is_vert = field:drop_ship(3)

	field:set_ship(x, y, 4, is_vert)
end

-- Проверка возможности установки корабля в позицию
function field:check_ship(x, y, l, is_vert)
	for xd, yd in field:ship_iter(x, y, l, is_vert) do
		if xd > 10 or xd < 1 or yd > 10 or yd < 1 then
			return false
		end

		for nx, ny in field:flap_around(xd, yd) do
			if field:get(nx, ny) ~= 0 then
				return false
			end
		end
	end

	return true
end

-- Установка корабля
function field:set_ship(x, y, l, is_vert)
	-- Рисуем заборчик около корабля (чтобы никто к нам не подошёл вплотную)
	for xd, yd in field:ship_iter(x, y, l, is_vert) do
		for nx, ny in field:flap_around(xd, yd) do
			field:set(nx, ny, nil)
		end
	end

	-- Рисуем сам корабль
	for xd, yd in field:ship_iter(x, y, l, is_vert) do
		field:set(xd, yd, self.num)
	end

	self.num = self.num + 1
end

-- Установка клетки корабля
function field:set(x, y, v)
	if type(x) == "number" then
		x = field:_d2l(x)
	end

	self.field[x][y] = v
end

-- Запрос значения клетки
function field:get(x, y)
	if type(x) == "number" then
		x = field:_d2l(x)
	end

	return self.field[x][y]
end


-- morse:words("АБ")

field:fill()
field:debug()
