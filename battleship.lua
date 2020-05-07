-- Если нас подключили не из Си, выходим
if msleep == nil then
	os.exit()
end

DEBUG = false
FAKE_INPUT = false

KILLED = 'F'
FIRED = 'f'
MISSED = 'm'

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

-- вывод отладки
function debug(str)
	if DEBUG then print(str) end
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
	debug('Ответ: '..str)

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
			elseif v  == FIRED then
				v = '🔥'
			-- стреляли, убили
			elseif v == KILLED then
				v = '💀'
			-- стреляли, мимо
			elseif v == MISSED then
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

--[[ убийство корабля — даётся одна из точек, все точки
этого корабля перекрашиваются ]]
function field:kill(x, y)
	self:set(x, y, KILLED)
	for x, y in self:flap_around(x, y) do
		if self:get(x, y) == FIRED then self:kill(x, y) end
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
	if v == FIRED or v == KILLED or v == MISSED then
		return 'М' -- Мимо
	end

	-- В клетке ничего — мимо
	if v == nil or v == 0 then
		self:set(x, y, MISSED)
		return 'М' -- Мимо
	end

	self:set(x, y, FIRED)

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


	self:kill(x, y)
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

	debug('\nВведено: '..str)

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
					debug('Введены координаты: '..coords, x, y)
					return x, y
				end
			end
		end

		debug('Введены ошибочные координаты: '..coords)
		morse:words("?")
	end
end

-- Пользовельский вводе не через морзянку
-- ввод только цифрами, 0 → 10
function debug_input_coords()
	local coords = io.read()
	if utf8.len(coords) >= 2 then
		local out = {}
		coords:gsub(
			".",
			function (ch) table.insert(out, ch == "0" and 10 or tonumber(ch)) end
		)

		local x, y = table.unpack(out)
		debug('Введены координаты: '..coords, x, y)

		return x, y
	end

	debug('Введены ошибочные координаты: '..coords)

	return
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

				if m ~= 0 and m ~= FIRED and m ~= MISSED then
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

			-- если это не отстутствие корабля и не промах
			if v ~= nil and v ~= 0 and v ~= MISSED then
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

		-- длина корабля — разница между минимумом и максимумом
		local len = maxx - minx + maxy - miny + 1
		-- сначала выбираем произвольное направление
		local dir = ({'-','|'})[math.random(1, 2)]
		
		-- для корабля длины один надо бы посмотреть по каким координатам что-то стоит вокруг
		if len == 1 then
			local x, y = maxx, maxy

			-- если стреляли вокруг и промахнулись, то мы знаем направление
			if y > 1 and self:get(x, y - 1) == MISSED and y < 10 and self:get(x, y + 1) == MISSED then
				dir = '-'
			elseif x > 1 and self:get(x - 1, y) == MISSED and x < 10 and self:get(x + 1, y) == MISSED then
				dir = '|'
			end
		else
			-- направление корабля, если по «иксу» координаты совпадают, значит Вертикальный
			dir = maxx == minx and '|' or '-'
		end

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
			died = l[1].value == KILLED,
		})
	end

	return info
end

-- Выбирает куда стрелять дальше по противнику
function field:next_fire()
	-- найдём какие фигуры игрока мы уже знаем
	local ships = self:figures()

	--[[ мы ещё не знаем никаких кораблей, будем
	стрелять по сетке, в расчёте убить четырёхпалубный ]]
	if #ships == 0 then
		return self:build_grid(4)[1]
	end

	local target = nil

	-- найдём неубитый корабль
	for _, ship in ipairs(ships) do
		if not ship['died'] then
			target = ship
			break
		end
	end

	-- Неубитых кораблей нет
	if target == nil then
		--[[ Надо найти какой самый длинный корабль остался
		в живых, для этого посчитаем наши корабли. У нас
		четыре типа кораблей, записано количество ]]
		local lens = { 4, 3, 2, 1, }

		for _, ship in ipairs(ships) do
			lens[ship['len']] = lens[ship['len']] - 1
		end

		--[[ остались количество кораблей, которые мы не убили,
		в ключах записана длина ]]
		for l = 4, 1, -1 do
			if lens[l] > 0 then
				--[[ если это не однопалубный, то делаем сетку
				для кораблей такого типа и стреляем в первую координату ]]
				if l > 1 then
					return self:build_grid(l)[1]
				else
					local coords = {}
					--[[ для кораблей длины один надо взять все свободные
					клетки и вернуть первую случайную координату, вокруг которых
					ничего нет ]]
					for x = 1, 10 do
						for y = 1, 10 do
							-- смотрим, пусто ли вокруг
							for xe, ye in self:flap_around(x, y) do
								local ch = self:get(xe, ye)
								if ch ~= 0 and ch ~= nil then goto smth_nearby end
							end

							table.insert(coords, {x, y})
							::smth_nearby::
						end
					end
					shuffle(coords)
					return coords[1]
				end
			end
		end

		-- Убиты все корабли
		return nil
	else
		-- Координата по которой надо искать края
		local coord1 = target['dir'] == '-' and 'x' or 'y'
		-- Вторая координата
		local coord2 = coord1 == 'x' and 'y' or 'x'

		-- координаты краёв
		local max = target['max'][coord1] + 1
		local min = target['min'][coord1] - 1

		local coord_value = target['max'][coord2]

		local coords = {}

		--[[ Добавляем координаты, только если они укладывааются в пределы поля
		и в них уже не стреляли ]]
		local c = {[coord1] = max, [coord2] = coord_value}

		if max <= 10 and self:get(c.x, c.y) ~= MISSED then
			table.insert(coords, c)
		end

		local c = {[coord1] = min, [coord2] = coord_value}
		if min >= 1 and self:get(c.x, c.y) ~= MISSED then
			table.insert(coords, c)
		end

		shuffle(coords)

		-- Выбираем первое значение из перемешанной таблицы
		return {coords[1].x, coords[1].y}
	end
end

-- Проверка — есть ли куда стрелять
function field:finished()
	--[[ Надо обойти всё поле и посмотреть:
	     а) есть ли куда стрелять
	     б) не убиты ли все корабли
	]]

	local fired = 0 -- убитых ячеек
	local empty = 100 -- свободных ячеек

	for x = 1, 10 do
		for y = 1, 10 do
			local v = self:get(x, y)
			if v ~= 0 and v ~= nil then
				empty = empty - 1
				if v == KILLED or v == FIRED then fired = fired + 1 end
			end
		end
	end

	-- всего кораблей
	local total = 1*4 + 3*2 + 2*3 + 4*1

	if fired >= total then
		return true, 'D' -- все убиты
	end

	if empty == 0 then
		return true, 'F' -- поле заполнено, ходить некуда
	end

	return false, '' -- ещё не всё
end

robot = field()
human = field()
robot:fill()

if DEBUG then robot:debug() end

while true do
	-- смотрим какие координаты дал нам пользователь
	repeat
		if FAKE_INPUT then x, y = debug_input_coords() else x, y = input_coords() end
	until x ~= nil

	-- стреляем по ним и сообщаем результат
	result = robot:fire(x, y)
	if result == nil then
		morse:words('НЕТ ХОДОВ')
	end

	morse:words(result)

	if DEBUG then robot:debug() end

	-- проверяем, не кончилась ли игра для робота
	finished, code = robot:finished()

	if finished then
		morse:words(code == 'D' and 'ВАША ПОБЕДА' or 'НЕТ ХОДОВ')
		break
	end

	-- если нет, то стреляем сами
	x, y = table.unpack(human:next_fire())
	-- для пользователя первую координату надо перевести в букву
	ch1 = ({'А','Б','В','Г','Д','Е','Ж','З','И','К'})[x]
	ch2 = y == 10 and "0" or tostring(y)
	debug('Компьютер стреляет: '..ch1..ch2)

	morse:words(ch1..ch2)

	-- теперь ждём что ответит пользователь: У — убил, Р — ранил, М — мимо
	while true do
		if FAKE_INPUT then answer = io.read() else answer = morse:input() end
		-- берём первый utf-8-символ и убираем 32 — делаем uppercase для русского
		ch = utf8.char(utf8.codepoint(answer) - 32)
		if ch == 'У' or ch == 'М' or ch == 'Р' then
			break
		else
			debug('Неправильный ввод, ещё раз.')
			morse:words('?')
		end
	end

	if ch == 'У' then
		human:kill(x, y)
	elseif ch == 'П' or ch == 'Р' then
		human:set(x, y, FIRED)
	else
		human:set(x, y, MISSED)
	end

	if DEBUG then human:debug() end

	-- проверяем, не кончилась ли игра для человека
	finished, code = human:finished()

	if finished then
		morse:words(code == 'D' and 'МОЯ ПОБЕДА' or 'НЕТ ХОДОВ')
		break
	end
end
