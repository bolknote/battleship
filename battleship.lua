-- Если нас подключили не из Си, выходим
if msleep == nil then
	os.exit()
end

--[[ Добавил энтропии, иначе при частых запусках значения,
получаемые через генератор, сильно повторяются ]]
local seed = string.byte(io.open("/dev/random", "rb"):read(1))
math.randomseed(os.time() + seed)

function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
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
field = {}
field.__index = field

setmetatable(field, {
  __call = function (cls, ...)
    return cls.new(...)
  end,
})

-- Конструктор
function field.new()
	local obj = {
		-- Порядковый номер выводимого корабля
		num = 1,

		field = {
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
			{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, },
		},
	}

	return setmetatable(obj, field)
end

-- Вывод поля боя (для отладки)
function field:debug()
	print('     А  Б  В  Г  Д  Е  Ж  З  И  К')

	for y = 1, 10 do
		io.write(string.format("%02s", y)..': ')

		for x in ipairs(self.field) do
			local v = self.field[x][y]
			if v == nil or v == 0 then
				v = '🌊'
			else
				v = '🚢'
			end
			io.write(v..' ')
		end
		print()
	end
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

--[[ Итератор для генерации спиральных координат,
начиная с краёв к центру ]]
function field:spiral_iter(is_vert)
	local min, max = 1, 10
	local insert = table.insert

	return function()
		coords = {}

		while min < max do
			if is_vert then
				for y = min, max do
					insert(coords, {min, y})
					insert(coords, {max, y})
				end
			else
				for x = min, max do
					insert(coords, {x, min})
					insert(coords, {x, max})
				end
			end

			min = min + 1
			max = max - 1

			shuffle(coords)
			return coords
		end
	end
end

-- Пытаемся разместить корабль на поле
function field:drop_ship(l)
	local is_vert = math.random() > .5

	for spiral in self:spiral_iter(is_vert) do
		for _, xy in ipairs(spiral) do
			if self:check_ship(xy[1], xy[2], l, is_vert) then
				return xy[1], xy[2], is_vert
			end
		end
	end
end

-- Заполнение поля кораблями
function field:fill()
	local long_ships = {4, 3, 2}

	--[[ Длинные корабли ставим по спирали (чтобы они были
	ближе к краям, такая стратегия ]]
	for q, l in ipairs(long_ships) do
		for _ = 1, q do
			local x, y, is_vert = self:drop_ship(l)
			self:set_ship(x, y, l, is_vert)
		end
	end

	-- Одиночные фигуры бросаем как придётся
	for _ = 1, 4 do
		local x, y
		repeat
			x, y = math.random(10), math.random(10)
		until self:check_ship(x, y, 1, true)
		
		self:set_ship(x, y, 1, true)
	end
end

-- Проверка возможности установки корабля в позицию
function field:check_ship(x, y, l, is_vert)
	for xd, yd in self:ship_iter(x, y, l, is_vert) do
		if xd > 10 or xd < 1 or yd > 10 or yd < 1 then
			return false
		end

		if self:get(xd, yd) ~= 0 then
			return false
		end
	end

	return true
end

-- Установка корабля
function field:set_ship(x, y, l, is_vert)
	-- Рисуем заборчик около корабля (чтобы никто к нам не подошёл вплотную)
	for xd, yd in self:ship_iter(x, y, l, is_vert) do
		for nx, ny in self:flap_around(xd, yd) do
			self:set(nx, ny)
		end
	end

	-- Рисуем сам корабль
	for xd, yd in self:ship_iter(x, y, l, is_vert) do
		self:set(xd, yd, self.num)
	end

	self.num = self.num + 1
end

-- Установка клетки корабля
function field:set(x, y, v)
	self.field[x][y] = v
end

-- Запрос значения клетки
function field:get(x, y)
	return self.field[x][y]
end

myf = field()
myf:fill()
myf:debug()

emf = field()

-- morse:words('ХОДИ')
print(shift_duration())
