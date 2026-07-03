let Module;
const fontFiles = { regular: null, bold: null, italic: null, bolditalic: null };

const INTERVALS = {
  reading: [[0x0020, 0x007E]],
  cyrillic: [[0x0400, 0x04FF], [0x0500, 0x052F]],
  latin: [[0x0080, 0x00FF], [0x0100, 0x024F]],
  greek: [[0x0370, 0x03FF]],
};

function log(msg) {
  const el = document.getElementById('log');
  el.innerHTML += `[${new Date().toLocaleTimeString()}] ${msg}<br>`;
  el.scrollTop = el.scrollHeight;
  console.log(msg);
}

function setStatus(msg, type = 'info') {
  const el = document.getElementById('status');
  el.className = `status ${type}`;
  el.textContent = msg;
}

// Инициализация FreeType WASM
async function initFreeType() {
  if (Module) return Module;
  setStatus('⏳ Загрузка FreeType WASM...', 'info');
  log('Initializing FreeType...');
  
  Module = await FreeType({
    locateFile: (path) => `freetype.${path.split('.').pop()}`
  });
  
  setStatus('✅ FreeType готов', 'success');
  log('FreeType initialized successfully');
  return Module;
}

// Слушаем выбор файлов
['regular', 'bold', 'italic', 'bolditalic'].forEach(style => {
  document.getElementById(style).addEventListener('change', (e) => {
    if (e.target.files[0]) {
      fontFiles[style] = e.target.files[0];
      log(`Выбран ${style}: ${e.target.files[0].name}`);
    }
  });
});

// Главная функция конвертации
async function startConversion() {
  if (!fontFiles.regular) {
    setStatus('❌ Сначала выберите Regular шрифт!', 'error');
    return;
  }
  
  const familyName = document.getElementById('family').value || 'MyFont';
  const sizes = Array.from(document.querySelectorAll('.size:checked')).map(c => parseInt(c.value));
  const unicodeSets = ['reading', 'cyrillic', 'latin', 'greek']
    .filter(id => document.getElementById(id).checked);
  
  const intervals = [];
  unicodeSets.forEach(set => intervals.push(...INTERVALS[set]));
  
  setStatus(`🔨 Начинаю конвертацию: ${sizes.length} размеров, ${intervals.length} интервалов`, 'info');
  log(`Family: ${familyName}, Sizes: ${sizes.join(', ')}`);
  
  try {
    const ft = await initFreeType();
    const results = [];
    
    for (const size of sizes) {
      setStatus(`🔨 Размер ${size}pt...`, 'info');
      log(`Processing size ${size}pt...`);
      
      const cpfont = await convertStyle(ft, fontFiles.regular, size, intervals, familyName);
      results.push({
        name: `${familyName}_${size}.cpfont`,
        data: cpfont
      });
      
      log(`✅ Size ${size}pt done: ${cpfont.length} bytes`);
    }
    
    // Скачиваем файлы
    for (const r of results) {
      const blob = new Blob([r.data], { type: 'application/octet-stream' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = r.name;
      a.click();
      URL.revokeObjectURL(url);
      log(`✅ Создан: ${r.name}`);
    }
    
    setStatus(`🎉 Готово! Создано файлов: ${results.length}`, 'success');
  } catch (e) {
    log(`❌ Ошибка: ${e.message}`);
    setStatus(`❌ Ошибка конвертации: ${e.message}`, 'error');
    console.error(e);
  }
}

// Конвертация одного стиля (упрощённая версия)
async function convertStyle(ft, fontFile, size, intervals, familyName) {
  const arrayBuffer = await fontFile.arrayBuffer();
  const fontData = new Uint8Array(arrayBuffer);
  
  // Загружаем шрифт в FreeType
  const facePtr = Module._malloc(fontData.length);
  Module.HEAPU8.set(fontData, facePtr);
  
  const face = Module._FT_New_Memory_Face(facePtr, fontData.length, 0);
  if (!face) {
    Module._free(facePtr);
    throw new Error('Не удалось загрузить шрифт');
  }
  
  // Устанавливаем размер
  Module._FT_Set_Char_Size(face, size << 6, size << 6, 150, 150);
  
  // Собираем глифы (упрощённо - полная реализация требует доступа к внутренним структурам FreeType)
  // В реальной версии нужно использовать Web Worker и полный API FreeType
  
  // Временная заглушка - создаём пустой .cpfont
  const buffer = new ArrayBuffer(1024);
  const view = new DataView(buffer);
  
  // Magic: "CPFONT"
  view.setUint8(0, 0x43); // C
  view.setUint8(1, 0x50); // P
  view.setUint8(2, 0x46); // F
  view.setUint8(3, 0x4F); // O
  view.setUint8(4, 0x4E); // N
  view.setUint8(5, 0x54); // T
  view.setUint8(6, 0x00);
  view.setUint8(7, 0x00);
  
  Module._FT_Done_Face(face);
  Module._free(facePtr);
  
  return new Uint8Array(buffer);
}

// Инициализация
window.addEventListener('load', () => {
  log('Конвертер готов к работе');
  setStatus('Готов к конвертации', 'success');
});