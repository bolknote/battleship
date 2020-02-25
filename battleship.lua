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
	field = {
		["А"] = {false, false, false, false, false, false, false, false, false, false, },
		["Б"] = {false, false, false, false, false, false, false, false, false, false, },
		["В"] = {false, false, false, false, false, false, false, false, false, false, },
		["Г"] = {false, false, false, false, false, false, false, false, false, false, },
		["Д"] = {false, false, false, false, false, false, false, false, false, false, },
		["Е"] = {false, false, false, false, false, false, false, false, false, false, },
		["Ж"] = {false, false, false, false, false, false, false, false, false, false, },
		["З"] = {false, false, false, false, false, false, false, false, false, false, },
		["И"] = {false, false, false, false, false, false, false, false, false, false, },
		["К"] = {false, false, false, false, false, false, false, false, false, false, },
	},
}

-- Вывод поля боя (для отладки)
function field:debug()
	local keys = {}

	for k in pairs(self.field) do
		table.insert(keys, k)
	end

	table.sort(keys)

	for y = 1, 10 do
		for _, x in ipairs(keys) do
			io.write((self.field[x][y] and '■' or '□')..' ')
		end
		print()
	end
end

-- Установка клетки корабля
function field:set(x, y)
	self.field[x][y] = true
end

-- Запрос значения клетки
function field:get(x, y)
	return self.field[x][y]
end

-- Если нас подключили не из Си, выходим
if msleep == nil then
	os.exit()
end

-- morse:words("АБ")

field:set('Б', 2)
field:debug()
