-- Если нас подключили не из Си, выходим
if msleep == nil then
	os.exit()
end

DEBUG = true

--[[ Добавил энтропии, иначе при частых запусках значения,
получаемые через генератор, сильно повторяются ]]
local seed = string.byte(io.open("/dev/random", "rb"):read(1))
math.randomseed(os.time() + seed)

-- Функция для перемешивания массива (таблицы)
function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

-- Работа с кодами Морзе
morse = {
	-- Длительность точки (от неё отталкиваются остальные задержки)
	delay = 100,

	table = {
		["А"]="._",
		["Б"]="_...",
		["В"]=".__",
		["Г"]="__.",
		["Д"]="_..",
		["Е"]=".",
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

function morse:find(s)
	for ch, seq in pairs(self.table) do
		if s == seq then
			return ch
		end
	end

	return nil
end

-- Вывод одного символа
function morse:char(ch)
	local table = assert(self.table[ch])

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
	if DEBUG then print('Ответ: '..str) end

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

		for x = 1, 10 do
			local v = self.field[x][y]
			-- пустая клетка
			if v == nil or v == 0 then
				v = '🌊'
			-- стреляли, ранили
			elseif v  == 'f' then
				v = '🔥'
			-- стреляли, убили
			elseif v == 'F' then
				v = '💀'
			-- стреляли, мимо
			elseif v == 'm' then
				v = '💥'
			else
			-- часть («палуба») корабля
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

-- Выстрел по клетке
function field:fire(x, y)
	--[[ У нас может быть такой результат:
	промах, ранил, убил (только для кораблей компьютера) ]]

	local v = self:get(x, y)

	-- В клетку уже стреляли — мимо
	if v == 'f' or v == 'F' or v == 'm' then
		return 'М' -- Мимо
	end

	-- В клетке ничего — мимо
	if v == nil or v == 0 then
		self:set(x, y, 'm')
		return 'М' -- Мимо
	end

	self:set(x, y, 'f')

	--[[ Имеет смысл только для кораблей компьютера:
	ищется, если ли ещё часть корабля с тем же номером,
	если есть, то корабль компьютера ещё не убили ]]
	for ty = 1, 10 do
		for tx = 1, 10 do
			if self:get(tx, ty) == v then
				return 'Р' -- Ранил
			end
		end
	end

	--[[ Этот случай интересен только в случае стрельбы по
	кораблям компьютера, поэтому мы не перекрашиваем убитый корабль —
	что корабль убит интересно только компьютеру в отношение игрока ]]

	return 'У' -- Убил
end

-- Декодируем букву
function morse:detect(buffer)
	local ch = morse:find(buffer)

	--[[ Если букву не удалось распознать, попробуем разбить
	последовательность на две части и найти две буквы]]
	if ch == nil then
		for i = 2, #buffer-1 do
			local b1, b2 = buffer:sub(1, i), buffer:sub(i+1)
			local ch1, ch2 = morse:find(b1), morse:find(b2)

			if ch1 ~= nil and ch2 ~= nil then
				return ch1..ch2
			end
		end

		return '?'
	end

	return ch
end

-- Ввод слова в коде Морзе с клавиатуры
function morse:input()
	local str, buffer, started = "", "", false

	while true do
		-- Пропускаем таймауты, если пользователь ещё ничего не нажимал
		repeat
			before, dkey = shift_duration(morse.delay * 10)
		until started or before ~= nil

		-- По таймауту считаем передачу законченной
		if before == nil then
			if buffer ~= "" then
				str  = str .. morse:detect(buffer)
			end
			break
		end

		--[[ Если это не первый символ и пауза больше утроенной точки,
		то это следующий символ ]]
		if started and before >= morse.delay * 3 then
			str  = str .. morse:detect(buffer)
			buffer = ""
			if DEBUG then io.write(' '); io.flush() end
		end

		--[[ Если только что стартанули, то нас не интересует
		before, там могло остаться значение от прошлого запуска]]
		local key = dkey > morse.delay * 3 and '_' or '.'

		if DEBUG then io.write(key); io.flush() end

		buffer = buffer .. key
		started = true
	end

	if DEBUG then print('\nВведено: '..str) end

	return str
end

-- Взаимодействие с пользователем для ввода двух координат
function input_coords()
	while true do
		local coords = ""

		repeat
			coords = coords .. morse:input()
		until utf8.len(coords) > 1

		if utf8.len(coords) == 2 then
			--[[ Переводим первый символ в число по порядку (codepoint возвращает код
			только первого символа), 1040 — код символа «А»,
			«А» → 1, «Б» → 2 и так далее ]]
			local x = utf8.codepoint(coords) - 1040 + 1
			 -- Поскольку «Й» в Морском бое пропускается, надо сдвинуть
			if x == 11 then
				x = 10
			end

			if x >= 1 and x <= 10 then
				-- Получаем второй символ (Луа очень плохо работает с UTF-8)
				local y = tonumber(coords:sub(utf8.offset(coords, 2), #coords))

				if y ~= nil then
					if DEBUG then print('Введены координаты: '..coords, x, y) end
					return x, y
				end
			end
		end

		print('Введены координаты: '..coords)
		morse:words("?")
	end
end

--[[ Строим решётку по которой будем стрелять,
чтобы найти какую-то фигуру, надо стрелять по решётке
такого же размера, а чтобы это не было однообразно,
перемешаем ]]
function field:build_grid(l)
	local x, y = 1, l
	local grid = {}

	while x <= 10 and y <= 10 do
		if self:get(x, y) == 0 then
			-- Посмотрим не стоит ли наша точка около корабля,
			-- рядом с кораблём нет смысла стрелятьы
			for nx, ny in self:flap_around(x, y) do
				local m = self:get(nx, ny)

				if m ~= 0 and m ~= 'f' then
					goto ship_nearby
				end
			end

			table.insert(grid, {x, y})
			::ship_nearby::
		end

		if y == 10 then
			x, y = x + 1, 1
		else
			y = y + l

			if y > 10 then
				x, y = x + 1, y - 10 + 1
			end
		end
	end

	shuffle(grid)
	return grid
end

-- Ищет на поле фигуры
function field:figures()
	--[[ Находим все фигуры, считая расстояния между точками, которые
	у нас уже записаны и новыми ]]
	local figures = {}

	for x = 1, 10 do
		for y = 1, 10 do
			local v = self:get(x, y)

			if v ~= nil and v ~= 0 then
				for _, l in ipairs(figures) do
					for _, f in ipairs(l) do
						-- Если точки рядом, значит они одной фигуры
						if math.abs(x - f[1]) + math.abs(y - f[2]) == 1 then
							table.insert(l, {x, y, value = v})
							goto found
						end
					end
				end
				-- Если точка никуда не добавилась, значит это первая точка корабля
				table.insert(figures, {{x, y, value = v}})
				::found::
			end
		end
	end

	--[[ Нужно упорядочить фигуры — записать длины найденных фигур,
	полные они или нет, а так же максимальную и минимальную точки ]]
	local info = {}

	for _, l in ipairs(figures) do
		-- в силу особенностей обхода младшие координаты идут первыми
		local minx, miny = table.unpack(l[1])
		local maxx, maxy = table.unpack(l[#l])
		-- длина коробля — разница между минимумом и максимумом
		local len = maxx - minx + maxy - miny + 1
		-- направление корабля, если по «иксу» координаты совпадают, значит Вертикальный
		local dir = maxx == minx and '|' or '-'

		table.insert(info, {
			-- минимальные координаты
			min = {x = minx, y = miny},
			-- максимальные координаты
			max = {x = maxx, y = maxy},
			-- длина корабля
			len = len,
			-- направление: «Вертикальный» или «Горизонтальный»
			dir = dir,
			-- для контроля, что корабль убит, хватит просмотра одного значения
			died = l[1].value == 'F',
		})
	end

	return info
end

myfield = field()
-- myfield:fill()

myfield:set(3, 1, 'f')
myfield:set(3, 2, 'f')
myfield:set(3, 3, 'f')

myfield:set(5, 1, 'F')
myfield:set(5, 2, 'F')
myfield:set(5, 3, 'F')

myfield:set(4, 5, 'F')
myfield:set(5, 5, 'F')

myfield:set(7, 7, 'F')

t = myfield:figures()
require('print_table')
print_table(t)

for _, v in ipairs(myfield:build_grid(4)) do
	myfield:fire(table.unpack(v))
end

myfield:debug()

-- while true do
-- 	myfield:debug()
-- 	x, y = input_coords()
-- 	morse:words(myfield:fire(x, y))
-- end
