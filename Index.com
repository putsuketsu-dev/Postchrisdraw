import React, { useState, useEffect, useRef } from 'react';
import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously, onAuthStateChanged, signInWithCustomToken } from 'firebase/auth';
import { 
  getFirestore, collection, addDoc, query, orderBy, onSnapshot, 
  serverTimestamp, updateDoc, doc, limit, where, deleteDoc, 
  enableIndexedDbPersistence 
} from 'firebase/firestore';
import { 
  QrCode, CheckCircle, RefreshCw, Smartphone, Monitor, DollarSign, 
  Clock, Trash2, ArrowRight, Settings, Plus, Minus, ShoppingBag, 
  History, X, List, Image as ImageIcon, Calculator, ChevronLeft, 
  Wifi, WifiOff, FileText, Download, PieChart, CloudOff, Camera, Zap, 
  Upload, Volume2, VolumeX, Bell, ThumbsUp, Edit2, ArrowUp, ArrowDown, Palette, Ban, TrendingUp
} from 'lucide-react';

// --- Firebase Configuration ---
const firebaseConfig = JSON.parse(__firebase_config);
const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const appId = typeof __app_id !== 'undefined' ? __app_id : 'default-app-id';

// --- Enable Offline Persistence ---
try {
  enableIndexedDbPersistence(db).catch((err) => {});
} catch (e) {}

// --- Utils ---
const formatCurrency = (amount) => new Intl.NumberFormat('zh-TW', { style: 'currency', currency: 'TWD', minimumFractionDigits: 0 }).format(amount);

// --- Sound Utility (Web Audio API) ---
const AudioContext = window.AudioContext || window.webkitAudioContext;

const playNotificationSound = () => {
  try {
    if (!AudioContext) return;
    const ctx = new AudioContext();
    const t = ctx.currentTime;
    const osc1 = ctx.createOscillator();
    const gain1 = ctx.createGain();
    osc1.frequency.setValueAtTime(880, t); 
    osc1.connect(gain1);
    gain1.connect(ctx.destination);
    gain1.gain.setValueAtTime(0.1, t);
    gain1.gain.exponentialRampToValueAtTime(0.001, t + 0.5);
    osc1.start(t);
    osc1.stop(t + 0.5);
    const osc2 = ctx.createOscillator();
    const gain2 = ctx.createGain();
    osc2.frequency.setValueAtTime(698.46, t + 0.2); 
    osc2.connect(gain2);
    gain2.connect(ctx.destination);
    gain2.gain.setValueAtTime(0.1, t + 0.2);
    gain2.gain.exponentialRampToValueAtTime(0.001, t + 1.2);
    osc2.start(t + 0.2);
    osc2.stop(t + 1.2);
  } catch (e) { console.error(e); }
};

const playSuccessSound = () => {
  try {
    if (!AudioContext) return;
    const ctx = new AudioContext();
    const t = ctx.currentTime;
    [1046.50, 1318.51, 1567.98].forEach((freq, i) => {
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.frequency.setValueAtTime(freq, t + i * 0.1);
        osc.type = 'sine';
        osc.connect(gain);
        gain.connect(ctx.destination);
        gain.gain.setValueAtTime(0.1, t + i * 0.1);
        gain.gain.exponentialRampToValueAtTime(0.001, t + i * 0.1 + 0.5);
        osc.start(t + i * 0.1);
        osc.stop(t + i * 0.1 + 0.5);
    });
  } catch (e) { console.error(e); }
};

// --- Helper: Compress Image ---
const compressImage = (file, quality = 0.7, maxWidth = 800) => {
    return new Promise((resolve) => {
        const reader = new FileReader();
        reader.readAsDataURL(file);
        reader.onload = (event) => {
            const img = new Image();
            img.src = event.target.result;
            img.onload = () => {
                const canvas = document.createElement('canvas');
                let width = img.width;
                let height = img.height;
                if (width > maxWidth) {
                    height = Math.round((height * maxWidth) / width);
                    width = maxWidth;
                }
                canvas.width = width;
                canvas.height = height;
                const ctx = canvas.getContext('2d');
                ctx.drawImage(img, 0, 0, width, height);
                resolve(canvas.toDataURL('image/jpeg', quality));
            };
        };
    });
};

const BG_COLORS = [
  { hex: '#ffffff', name: '白' },
  { hex: '#fee2e2', name: '紅' },
  { hex: '#ffedd5', name: '橘' },
  { hex: '#fef3c7', name: '黃' },
  { hex: '#dcfce7', name: '綠' },
  { hex: '#dbeafe', name: '藍' },
  { hex: '#f3e8ff', name: '紫' },
  { hex: '#1f2937', name: '黑' },
];

const TEXT_COLORS = [
  { hex: '#1f2937', name: '黑' },
  { hex: '#ffffff', name: '白' },
  { hex: '#dc2626', name: '紅' },
  { hex: '#2563eb', name: '藍' },
];

// --- Component: Login / Role Selection ---
const RoleSelection = ({ onSelectRole }) => (
  <div className="flex flex-col items-center justify-center min-h-screen bg-gray-100 p-4 select-none">
    <div className="bg-white p-8 rounded-2xl shadow-xl max-w-md w-full text-center">
      <h1 className="text-3xl font-bold text-gray-800 mb-2">店鋪結帳同步系統</h1>
      <p className="text-gray-500 mb-8">銷售統計與修正版 v10.0</p>
      
      <div className="space-y-4">
        <button 
          onClick={() => onSelectRole('outside')}
          className="w-full flex items-center justify-center p-6 bg-blue-600 text-white rounded-xl hover:bg-blue-700 transition shadow-lg active:scale-95 duration-200"
        >
          <Camera className="w-8 h-8 mr-4" />
          <div className="text-left">
            <div className="font-bold text-xl">我是騎樓人員</div>
            <div className="text-blue-100 text-sm">點餐、修正數量、拍照</div>
          </div>
        </button>

        <button 
          onClick={() => onSelectRole('bar')}
          className="w-full flex items-center justify-center p-6 bg-emerald-600 text-white rounded-xl hover:bg-emerald-700 transition shadow-lg active:scale-95 duration-200"
        >
          <PieChart className="w-8 h-8 mr-4" />
          <div className="text-left">
            <div className="font-bold text-xl">我是吧台人員</div>
            <div className="text-emerald-100 text-sm">接收訂單、銷售報表、作廢</div>
          </div>
        </button>
      </div>
    </div>
  </div>
);

// --- Component: Sales Report Modal ---
const SalesReportModal = ({ onClose }) => {
  const [stats, setStats] = useState({ total: 0, count: 0, items: {}, raw: [] });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const startOfToday = new Date();
    startOfToday.setHours(0, 0, 0, 0);

    const q = query(
      collection(db, 'artifacts', appId, 'public', 'data', 'orders'),
      where('createdAt', '>=', startOfToday),
      orderBy('createdAt', 'desc')
    );

    const unsub = onSnapshot(q, (snap) => {
      let total = 0;
      let count = 0;
      let itemsAgg = {};
      let raw = [];

      snap.docs.forEach(doc => {
        const d = { id: doc.id, ...doc.data() };
        // Exclude void orders from stats
        if (d.status !== 'void') {
          total += d.amount;
          count++;
          raw.push(d);

          if (d.items && Array.isArray(d.items)) {
            d.items.forEach(item => {
              if (!itemsAgg[item.name]) itemsAgg[item.name] = { qty: 0, total: 0 };
              itemsAgg[item.name].qty += item.qty;
              itemsAgg[item.name].total += (item.price * item.qty);
            });
          }
        }
      });

      setStats({ total, count, items: itemsAgg, raw });
      setLoading(false);
    });
    return () => unsub();
  }, []);

  const downloadCSV = () => {
    let csv = "\uFEFF報表日期," + new Date().toLocaleDateString() + "\n";
    csv += "總營業額," + stats.total + "\n";
    csv += "總單數," + stats.count + "\n\n";
    csv += "--- 品項銷售排行 ---\n品項,數量,金額\n";
    Object.entries(stats.items)
      .sort((a, b) => b[1].qty - a[1].qty)
      .forEach(([name, data]) => {
        csv += `${name},${data.qty},${data.total}\n`;
      });
    
    csv += "\n--- 交易明細 ---\n時間,內容,金額,狀態\n";
    stats.raw.forEach(o => {
       const time = o.createdAt?.toDate().toLocaleTimeString() || '';
       const desc = (o.itemsDesc || '').replace(/"/g, '""');
       const statusMap = { 'synced': '已完成', 'paid': '待入帳', 'scanning': '待掃碼', 'pending': '未付款' };
       csv += `${time},"${desc}",${o.amount},${statusMap[o.status] || o.status}\n`;
    });

    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `日結報表_${new Date().toLocaleDateString()}.csv`;
    link.click();
  };

  return (
    <div className="absolute inset-0 z-[70] bg-black/50 flex items-center justify-center p-4 backdrop-blur-sm animate-in fade-in">
      <div className="bg-white w-full max-w-lg rounded-2xl shadow-2xl flex flex-col max-h-[90vh]">
        <div className="p-4 border-b flex justify-between items-center bg-emerald-700 text-white rounded-t-2xl">
          <h3 className="font-bold text-lg flex items-center"><TrendingUp className="mr-2"/> 本日營收統計</h3>
          <button onClick={onClose} className="bg-emerald-800/50 p-1 rounded-full"><X/></button>
        </div>
        
        <div className="flex-1 overflow-y-auto p-4 bg-gray-50">
           {loading ? <RefreshCw className="animate-spin mx-auto mt-10 text-gray-400"/> : (
             <>
               <div className="grid grid-cols-2 gap-3 mb-4">
                  <div className="bg-white p-4 rounded-xl shadow-sm border border-emerald-100 text-center">
                     <div className="text-gray-500 text-xs font-bold">今日營業額</div>
                     <div className="text-3xl font-bold text-emerald-600">${stats.total}</div>
                  </div>
                  <div className="bg-white p-4 rounded-xl shadow-sm border border-blue-100 text-center">
                     <div className="text-gray-500 text-xs font-bold">有效單數</div>
                     <div className="text-3xl font-bold text-blue-600">{stats.count}</div>
                  </div>
               </div>

               <h4 className="font-bold text-gray-700 mb-2 text-sm flex items-center"><ShoppingBag size={14} className="mr-1"/> 品項排行</h4>
               <div className="bg-white rounded-xl shadow-sm overflow-hidden border border-gray-100 mb-4">
                  <table className="w-full text-sm">
                    <thead className="bg-gray-50 text-gray-500 border-b">
                      <tr><th className="p-2 text-left">品名</th><th className="p-2 text-right">數</th><th className="p-2 text-right">額</th></tr>
                    </thead>
                    <tbody className="divide-y">
                      {Object.keys(stats.items).length === 0 ? <tr><td colSpan="3" className="p-4 text-center text-gray-300">無資料</td></tr> :
                        Object.entries(stats.items).sort((a,b) => b[1].qty - a[1].qty).map(([name, d]) => (
                          <tr key={name}>
                            <td className="p-2 font-medium text-gray-700">{name}</td>
                            <td className="p-2 text-right">{d.qty}</td>
                            <td className="p-2 text-right text-gray-400">${d.total}</td>
                          </tr>
                        ))
                      }
                    </tbody>
                  </table>
               </div>
             </>
           )}
        </div>

        <div className="p-4 border-t bg-white rounded-b-2xl">
           <button onClick={downloadCSV} className="w-full bg-emerald-600 text-white py-3 rounded-xl font-bold shadow-lg flex items-center justify-center active:scale-95 transition">
              <Download className="mr-2"/> 匯出 Excel 報表
           </button>
        </div>
      </div>
    </div>
  );
};

// --- Component: Product Management (Updated for +/-) ---
const MenuSelector = ({ onAddToCart, onRemoveFromCart, cart, db }) => {
  const [products, setProducts] = useState([]);
  const [categories, setCategories] = useState(['所有']);
  const [selectedCategory, setSelectedCategory] = useState('所有');
  const [isEditingMode, setIsEditingMode] = useState(false);

  // Add Product States
  const [newProdName, setNewProdName] = useState('');
  const [newProdPrice, setNewProdPrice] = useState('');
  const [newProdCategory, setNewProdCategory] = useState('');

  // Edit Product States
  const [editingId, setEditingId] = useState(null);
  const [editFormData, setEditFormData] = useState({ name: '', price: '', category: '', bgColor: '#ffffff', textColor: '#1f2937' });

  useEffect(() => {
    const q = query(collection(db, 'artifacts', appId, 'public', 'data', 'products'));
    const unsub = onSnapshot(q, (snap) => {
      const prods = snap.docs.map(d => ({ id: d.id, ...d.data() }));
      prods.sort((a, b) => {
        const orderA = a.order !== undefined ? a.order : 999999;
        const orderB = b.order !== undefined ? b.order : 999999;
        if (orderA !== orderB) return orderA - orderB;
        return (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0);
      });
      setProducts(prods);
      const cats = new Set(['所有']);
      prods.forEach(p => { if (p.category) cats.add(p.category); });
      setCategories(Array.from(cats));
    });
    return () => unsub();
  }, [db]);

  const addProduct = async () => {
    if (!newProdName || !newProdPrice) return;
    try {
      const maxOrder = products.reduce((max, p) => (p.order > max ? p.order : max), 0);
      await addDoc(collection(db, 'artifacts', appId, 'public', 'data', 'products'), {
        name: newProdName, 
        price: Number(newProdPrice), 
        category: newProdCategory || '一般', 
        order: maxOrder + 1,
        bgColor: '#ffffff',
        textColor: '#1f2937',
        createdAt: serverTimestamp()
      });
      setNewProdName(''); setNewProdPrice(''); setNewProdCategory('');
    } catch(e) {}
  };

  const deleteProduct = async (id, e) => {
    e.stopPropagation();
    if(confirm('確定刪除此品項？')) await deleteDoc(doc(db, 'artifacts', appId, 'public', 'data', 'products', id));
  };

  const startEdit = (p) => {
    setEditingId(p.id);
    setEditFormData({ name: p.name, price: p.price, category: p.category || '一般', bgColor: p.bgColor || '#ffffff', textColor: p.textColor || '#1f2937' });
  };

  const saveEdit = async (id) => {
    try {
      await updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'products', id), {
          name: editFormData.name,
          price: Number(editFormData.price),
          category: editFormData.category,
          bgColor: editFormData.bgColor,
          textColor: editFormData.textColor
      });
      setEditingId(null);
    } catch(e) {}
  };

  const moveProduct = async (index, direction, e) => {
    e.stopPropagation();
    const currentProd = filteredProducts[index];
    const targetProd = filteredProducts[index + direction];
    if (!targetProd) return;
    const cOrder = currentProd.order !== undefined ? currentProd.order : index;
    const tOrder = targetProd.order !== undefined ? targetProd.order : (index + direction);
    try {
      await updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'products', currentProd.id), { order: tOrder });
      await updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'products', targetProd.id), { order: cOrder });
    } catch (e) {}
  };

  const filteredProducts = selectedCategory === '所有' ? products : products.filter(p => p.category === selectedCategory);

  return (
    <div className="flex flex-col h-full bg-gray-50 overflow-hidden">
      {/* Category Bar */}
      <div className="flex-none p-2 bg-white border-b overflow-x-auto whitespace-nowrap scrollbar-hide flex gap-2 items-center">
        <button 
            onClick={() => { setIsEditingMode(!isEditingMode); setEditingId(null); }} 
            className={`px-3 py-2 rounded-lg text-sm font-bold border flex items-center shrink-0 transition-colors ${isEditingMode ? 'bg-red-50 text-red-600 border-red-100' : 'bg-blue-50 text-blue-600 border-blue-100'}`}
        >
           {isEditingMode ? <X size={16} className="mr-1"/> : <Edit2 size={16} className="mr-1"/>}
           {isEditingMode ? '完成' : '編輯'}
        </button>
        {categories.map(cat => (
          <button key={cat} onClick={() => setSelectedCategory(cat)}
            className={`px-4 py-2 rounded-lg text-sm font-bold transition-colors ${selectedCategory === cat ? 'bg-gray-800 text-white shadow' : 'bg-white text-gray-600 border border-gray-200'}`}>
            {cat}
          </button>
        ))}
      </div>

      {/* Add Product Form (Edit Mode Only) */}
      {isEditingMode && (
        <div className="flex-none p-3 bg-blue-50 border-b border-blue-100 grid gap-2 animate-in slide-in-from-top-2">
          <p className="text-xs text-blue-400 font-bold mb-1">新增商品：</p>
          <div className="flex gap-2">
             <input placeholder="品名" className="flex-[2] p-2 rounded border text-sm" value={newProdName} onChange={e => setNewProdName(e.target.value)}/>
             <input type="number" placeholder="$" className="flex-1 p-2 rounded border text-sm" value={newProdPrice} onChange={e => setNewProdPrice(e.target.value)}/>
          </div>
          <div className="flex gap-2">
             <input list="category-list" placeholder="分類" className="flex-[2] p-2 rounded border text-sm" value={newProdCategory} onChange={e => setNewProdCategory(e.target.value)}/>
             <datalist id="category-list">{categories.filter(c => c !== '所有').map(c => <option key={c} value={c} />)}</datalist>
             <button onClick={addProduct} className="flex-1 bg-blue-600 text-white rounded font-bold text-sm shadow-sm">新增</button>
          </div>
        </div>
      )}

      {/* Product Grid */}
      <div className="flex-1 overflow-y-auto p-2 grid grid-cols-2 gap-2 content-start pb-24 overscroll-none">
        {filteredProducts.map((p, index) => {
          const inCart = cart.find(c => c.id === p.id);
          const isEditing = editingId === p.id;

          if (isEditing) {
              return (
                <div key={p.id} className="col-span-2 p-3 rounded-xl border border-blue-400 bg-white shadow-lg flex flex-col gap-3 relative z-20">
                    <div className="flex justify-between items-center border-b pb-2 mb-1">
                        <span className="font-bold text-blue-600">編輯中</span>
                        <div className="flex gap-2">
                            <button onClick={() => saveEdit(p.id)} className="bg-green-500 text-white px-3 py-1 rounded text-xs font-bold">儲存</button>
                            <button onClick={() => setEditingId(null)} className="bg-gray-200 text-gray-600 px-3 py-1 rounded text-xs font-bold">取消</button>
                        </div>
                    </div>
                    <div className="grid grid-cols-2 gap-2">
                        <input className="col-span-2 w-full p-2 border rounded font-bold" value={editFormData.name} onChange={e => setEditFormData({...editFormData, name: e.target.value})}/>
                        <input className="w-full p-2 border rounded" type="number" value={editFormData.price} onChange={e => setEditFormData({...editFormData, price: e.target.value})}/>
                        <input className="w-full p-2 border rounded" list="category-list" value={editFormData.category} onChange={e => setEditFormData({...editFormData, category: e.target.value})}/>
                    </div>
                    <div className="flex gap-4 items-center bg-gray-50 p-2 rounded border">
                        <div className="flex gap-1 items-center overflow-x-auto scrollbar-hide">
                            <span className="text-xs text-gray-400 mr-1">底色:</span>
                            {BG_COLORS.map(c => (<button key={c.hex} onClick={() => setEditFormData({...editFormData, bgColor: c.hex})} className={`w-6 h-6 rounded-full border shadow-sm ${editFormData.bgColor === c.hex ? 'ring-2 ring-blue-500 scale-110' : ''}`} style={{backgroundColor: c.hex}}/>))}
                        </div>
                        <div className="w-px h-6 bg-gray-300 mx-1"></div>
                        <div className="flex gap-1 items-center">
                            <span className="text-xs text-gray-400 mr-1">字色:</span>
                            {TEXT_COLORS.map(c => (<button key={c.hex} onClick={() => setEditFormData({...editFormData, textColor: c.hex})} className={`w-6 h-6 rounded-full border shadow-sm ${editFormData.textColor === c.hex ? 'ring-2 ring-blue-500 scale-110' : ''}`} style={{backgroundColor: c.hex}}/>))}
                        </div>
                    </div>
                </div>
              )
          }

          return (
            <div key={p.id} className="relative group select-none">
                <button 
                  onClick={() => !isEditingMode && onAddToCart(p)}
                  className={`w-full p-3 rounded-xl border text-left relative active:scale-95 transition-transform flex flex-col justify-between min-h-[80px]
                    ${inCart ? 'ring-2 ring-blue-500 border-blue-500' : 'border-gray-200 shadow-sm'}
                    ${isEditingMode ? 'opacity-90' : ''}`}
                  style={{ backgroundColor: p.bgColor || '#ffffff', color: p.textColor || '#1f2937' }}
                >
                  <div className="font-bold text-sm line-clamp-1 pr-4">{p.name}</div>
                  <div className="flex justify-between items-end mt-1">
                      <span className="font-bold text-lg">${p.price}</span>
                      {isEditingMode && <span className="text-[10px] bg-black/10 px-1 rounded">{p.category}</span>}
                  </div>
                </button>
                
                {/* Quantity Controls (Normal Mode) */}
                {inCart && !isEditingMode && (
                  <div className="absolute top-2 right-2 flex flex-col items-center gap-1 z-10">
                      <div className="bg-blue-600 text-white text-sm w-7 h-7 rounded-full flex items-center justify-center font-bold shadow-sm">{inCart.qty}</div>
                      <button 
                        onClick={(e) => { e.stopPropagation(); onRemoveFromCart(p.id); }}
                        className="bg-red-100 text-red-600 w-7 h-7 rounded-full flex items-center justify-center hover:bg-red-200 active:scale-90 transition shadow-sm border border-red-200"
                      >
                        <Minus size={16} />
                      </button>
                  </div>
                )}
                
                {/* Edit Mode Controls */}
                {isEditingMode && (
                  <>
                    <div className="absolute top-1 right-1 flex gap-1 z-10">
                        <button onClick={(e) => { e.stopPropagation(); startEdit(p); }} className="p-1.5 bg-white text-blue-600 border border-blue-200 rounded-full shadow-sm hover:bg-blue-50"><Edit2 size={14}/></button>
                        <button onClick={(e) => deleteProduct(p.id, e)} className="p-1.5 bg-white text-red-600 border border-red-200 rounded-full shadow-sm hover:bg-red-50"><Trash2 size={14}/></button>
                    </div>
                    <div className="absolute bottom-1 right-1 flex gap-1 z-10">
                       {index > 0 && <button onClick={(e) => moveProduct(index, -1, e)} className="p-1 bg-gray-100 text-gray-600 rounded shadow hover:bg-gray-200"><ArrowUp size={12}/></button>}
                       {index < filteredProducts.length - 1 && <button onClick={(e) => moveProduct(index, 1, e)} className="p-1 bg-gray-100 text-gray-600 rounded shadow hover:bg-gray-200"><ArrowDown size={12}/></button>}
                    </div>
                  </>
                )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

// --- Component: Outside View ---
const OutsideView = ({ user }) => {
  const [isOnline, setIsOnline] = useState(navigator.onLine);
  const [cart, setCart] = useState(() => JSON.parse(localStorage.getItem('cart') || '[]'));
  const [qrImage, setQrImage] = useState(() => localStorage.getItem('qrImage') || '');

  // UI State
  const [step, setStep] = useState('input');
  const [historyOpen, setHistoryOpen] = useState(false);
  const [currentOrderId, setCurrentOrderId] = useState(null);
  const [isProcessingImg, setIsProcessingImg] = useState(false);
  const [barConfirmed, setBarConfirmed] = useState(false); 

  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    return () => {
        window.removeEventListener('online', handleOnline);
        window.removeEventListener('offline', handleOffline);
    };
  }, []);

  useEffect(() => {
    localStorage.setItem('cart', JSON.stringify(cart));
  }, [cart]);

  // Listener for Bar Confirmation
  useEffect(() => {
    if (!currentOrderId) return;
    const unsub = onSnapshot(doc(db, 'artifacts', appId, 'public', 'data', 'orders', currentOrderId), (docSnap) => {
      if (docSnap.exists()) {
        const data = docSnap.data();
        if (data.status === 'synced' && step !== 'success' && !barConfirmed) {
          if (navigator.vibrate) navigator.vibrate([100, 50, 100]); 
          playSuccessSound(); 
          setBarConfirmed(true); 
          setTimeout(() => { finishTransaction(); setBarConfirmed(false); }, 2500); 
        }
      }
    });
    return () => unsub();
  }, [currentOrderId, step, barConfirmed]);

  const addToCart = (product) => {
    setCart(prev => {
      const exist = prev.find(p => p.id === product.id);
      if (exist) return prev.map(p => p.id === product.id ? { ...p, qty: p.qty + 1 } : p);
      return [...prev, { ...product, qty: 1 }];
    });
  };
  
  const removeFromCart = (id) => {
    setCart(prev => {
      const exist = prev.find(p => p.id === id);
      if (exist?.qty > 1) return prev.map(p => p.id === id ? { ...p, qty: p.qty - 1 } : p);
      return prev.filter(p => p.id !== id);
    });
  };

  const getFinalAmount = () => cart.reduce((sum, item) => sum + (item.price * item.qty), 0);
  
  const handleStoreQrUpload = (e) => {
    const file = e.target.files[0];
    if (file) {
      const reader = new FileReader();
      reader.onloadend = () => { setQrImage(reader.result); localStorage.setItem('qrImage', reader.result); };
      reader.readAsDataURL(file);
    }
  };

  const handleCustomerCameraCapture = async (e) => {
    const file = e.target.files[0];
    if (!file) return;
    setIsProcessingImg(true);
    try {
        const compressedDataUrl = await compressImage(file);
        await createOrder(compressedDataUrl);
    } catch (err) { alert("圖片處理失敗，請重試"); } finally {
        setIsProcessingImg(false);
        e.target.value = ''; 
    }
  };

  const createOrder = async (capturedImage = null) => {
    const finalAmount = getFinalAmount();
    if (finalAmount === 0) return;
    
    let itemsDesc = cart.map(i => `${i.name} x${i.qty}`).join(', ');
    let itemsData = cart;

    const orderData = {
      amount: finalAmount, 
      itemsDesc, 
      items: itemsData,
      status: capturedImage ? 'scanning' : 'pending', 
      paymentImage: capturedImage,
      createdAt: serverTimestamp(),
      createdBy: user.uid, 
      location: 'outside'
    };

    try {
        const ref = await addDoc(collection(db, 'artifacts', appId, 'public', 'data', 'orders'), orderData);
        setCurrentOrderId(ref.id);
        if (capturedImage) setStep('scanning');
        else setStep('payment');
    } catch (e) { alert("儲存錯誤"); }
  };

  const markAsPaid = async () => {
    if (!currentOrderId) return;
    try {
        await updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'orders', currentOrderId), { status: 'paid', paidAt: serverTimestamp() });
        finishTransaction();
    } catch(e) { finishTransaction(); }
  };

  const finishTransaction = () => {
      setStep('success');
      setTimeout(() => {
        setStep('input');
        setCart([]); setCurrentOrderId(null);
      }, 2000);
  };

  return (
    <div className="flex flex-col h-[100dvh] bg-gray-50 max-w-md mx-auto shadow-2xl overflow-hidden relative select-none overscroll-none touch-none">
      
      {/* --- Bar Confirmation Overlay --- */}
      {barConfirmed && (
         <div className="absolute inset-0 z-[60] bg-green-500 flex flex-col items-center justify-center text-white animate-in zoom-in duration-300">
             <ThumbsUp size={120} className="mb-6 animate-bounce" />
             <h2 className="text-4xl font-bold mb-2">吧台已確認！</h2>
             <p className="text-xl opacity-90">交易完成，可放行客人</p>
         </div>
      )}

      {/* Header */}
      <div className={`border-b px-4 py-3 flex justify-between items-center shadow-sm z-20 h-14 shrink-0 transition-colors duration-500 ${isOnline ? 'bg-white' : 'bg-orange-50'}`}>
        <div className="flex items-center gap-2">
           <div className={`flex items-center px-2 py-1 rounded-full text-xs font-bold border ${isOnline ? 'bg-green-100 text-green-700 border-green-200' : 'bg-orange-100 text-orange-700 border-orange-200'}`}>
              {isOnline ? <Wifi size={14} className="mr-1"/> : <WifiOff size={14} className="mr-1"/>}
              {isOnline ? '連線正常' : '離線模式'}
           </div>
        </div>
        <button onClick={() => setHistoryOpen(true)}><List className="text-gray-600" size={24}/></button>
      </div>

      {/* Main Body */}
      <div className="flex-1 flex flex-col relative overflow-hidden bg-gray-50">
        
        {step === 'input' && (
          <div className="flex flex-col h-full">
            <div className="bg-white p-4 text-center shrink-0 border-b shadow-sm z-10 flex flex-col justify-center">
               <p className="text-xs text-gray-400 mb-1">本次收款</p>
               <div className="text-5xl font-bold text-gray-800 tracking-tight leading-none">
                 {formatCurrency(getFinalAmount())}
               </div>
               <p className="text-xs text-gray-400 mt-2">共 {cart.reduce((a,c)=>a+c.qty,0)} 項商品</p>
            </div>

            <div className="flex-1 overflow-hidden relative">
               <MenuSelector onAddToCart={addToCart} onRemoveFromCart={removeFromCart} cart={cart} db={db} />
            </div>
          </div>
        )}

        {/* --- Step: Scanning Mode --- */}
        {step === 'scanning' && (
          <div className="flex-1 flex flex-col items-center justify-center bg-gray-900 text-white p-6 text-center animate-in fade-in duration-300">
             <div className="w-32 h-32 rounded-full flex items-center justify-center mb-8 relative">
                <span className="absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-20 animate-ping"></span>
                <div className="bg-gray-800 rounded-full w-full h-full flex items-center justify-center border-4 border-blue-500 z-10">
                   <Monitor className="w-16 h-16 text-blue-400" />
                </div>
             </div>
             <h3 className="text-2xl font-bold mb-2">已傳送，等待吧台確認</h3>
             <p className="text-gray-400 mb-8">吧台完成掃描後，此畫面會自動跳轉</p>
             <p className="text-4xl font-bold text-white mb-12">${getFinalAmount()}</p>
             <button onClick={markAsPaid} className="text-gray-500 text-sm underline hover:text-white">網路有問題？手動強制完成</button>
          </div>
        )}

        {/* --- Step: Standard Payment --- */}
        {step === 'payment' && (
          <div className="flex-1 flex flex-col items-center justify-center bg-white p-6 text-center animate-in slide-in-from-right duration-200">
            <div className="bg-gray-50 p-2 rounded-2xl shadow-inner border border-gray-100 mb-6 w-64 h-64 flex items-center justify-center relative">
              {qrImage ? (
                 <img src={qrImage} alt="QR" className="w-full h-full object-contain rounded-lg" />
              ) : (
                <div className="text-gray-400 flex flex-col items-center">
                   <ImageIcon size={48} className="mb-2 opacity-30" />
                   <span className="text-sm">未設定 QR 圖片</span>
                   <label className="mt-4 px-4 py-2 bg-blue-100 text-blue-600 rounded-lg text-sm font-bold cursor-pointer">
                      上傳圖片 <input type="file" accept="image/*" onChange={handleStoreQrUpload} className="hidden" />
                   </label>
                </div>
              )}
            </div>
            <div className="mb-2">
                <p className="text-gray-400 text-sm">本次收款</p>
                <p className="text-5xl font-bold text-gray-800 tracking-tight">${getFinalAmount()}</p>
            </div>
            <button onClick={markAsPaid} className="w-full bg-green-500 text-white p-4 rounded-xl font-bold text-lg shadow-lg shadow-green-200 mt-4 active:scale-95 transition">
              <CheckCircle className="inline mr-2 w-5 h-5" /> 確認顧客已付款
            </button>
            <button onClick={() => setStep('input')} className="mt-4 text-gray-400">返回修改</button>
          </div>
        )}

        {step === 'success' && (
          <div className="flex-1 flex flex-col items-center justify-center bg-green-50 p-8 text-center animate-in zoom-in duration-300">
             <div className="w-24 h-24 bg-green-100 rounded-full flex items-center justify-center mb-6">
              <CheckCircle className="w-12 h-12 text-green-600" />
            </div>
            <h3 className="text-3xl font-bold text-green-800 mb-2">已完成</h3>
            <p className="text-green-600 text-lg">${getFinalAmount()}</p>
          </div>
        )}
      </div>

      {/* Footer Buttons */}
      {step === 'input' && (
        <div className="bg-white border-t border-gray-200 p-4 shadow-[0_-4px_10px_rgba(0,0,0,0.05)] shrink-0 z-20 pb-8 flex gap-3">
             <label className={`flex-[2] bg-gray-900 text-white rounded-xl shadow-lg h-14 text-lg font-bold flex items-center justify-center active:scale-[0.98] transition cursor-pointer relative overflow-hidden ${getFinalAmount() === 0 ? 'opacity-50 pointer-events-none' : ''}`}>
               <input type="file" accept="image/*" capture="environment" onChange={handleCustomerCameraCapture} className="hidden" disabled={getFinalAmount() === 0}/>
               {isProcessingImg ? <><RefreshCw className="animate-spin mr-2"/> 處理中...</> : <><Camera className="w-6 h-6 mr-2" /> 拍客人付款碼</>}
             </label>
             <button onClick={() => { if(getFinalAmount() > 0) createOrder(); }} disabled={getFinalAmount() === 0} className="flex-1 bg-blue-100 text-blue-700 rounded-xl h-14 text-sm font-bold disabled:opacity-50 active:scale-[0.98] transition flex flex-col items-center justify-center leading-tight">
               <QrCode className="w-5 h-5 mb-1" /> 顯示收款碼
             </button>
        </div>
      )}

      {/* History Overlay */}
      {historyOpen && (
        <div className="absolute inset-0 z-50 bg-white flex flex-col animate-in slide-in-from-left">
           <div className="p-4 border-b flex justify-between items-center bg-gray-50">
             <h3 className="font-bold text-lg text-gray-700">今日紀錄</h3>
             <button onClick={() => setHistoryOpen(false)} className="bg-gray-200 p-2 rounded-full"><X size={20}/></button>
           </div>
           <OrderHistoryList user={user} type="outside" />
        </div>
      )}
    </div>
  );
};

// --- Shared: History List ---
const OrderHistoryList = ({ user }) => {
  const [history, setHistory] = useState([]);
  useEffect(() => {
    const startOfToday = new Date(); startOfToday.setHours(0,0,0,0);
    const q = query(collection(db, 'artifacts', appId, 'public', 'data', 'orders'), where('createdAt', '>=', startOfToday), orderBy('createdAt', 'desc'), limit(50));
    const unsub = onSnapshot(q, (snap) => {
      setHistory(snap.docs.map(d => ({id: d.id, ...d.data()})));
    });
    return () => unsub();
  }, []);
  const formatTime = (ts) => ts ? ts.toDate().toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'}) : '...';
  
  return (
    <div className="flex-1 overflow-y-auto bg-gray-50 p-4 space-y-3 pb-20">
       {history.length === 0 && <div className="text-center text-gray-400 mt-10">尚無紀錄</div>}
       {history.map(order => (
         <div key={order.id} className={`bg-white p-4 rounded-xl shadow-sm flex justify-between items-center border ${order.status === 'void' ? 'border-red-200 bg-red-50 opacity-60' : 'border-gray-100'}`}>
            <div>
               <div className="flex items-center gap-2 mb-1">
                 <span className="text-xs font-mono text-gray-400 bg-gray-100 px-2 py-0.5 rounded">{formatTime(order.createdAt)}</span>
                 {order.status === 'scanning' && <span className="text-xs bg-purple-100 text-purple-600 px-2 py-0.5 rounded-full font-bold">待內場掃碼</span>}
                 {order.status === 'paid' && <span className="text-xs bg-red-100 text-red-600 px-2 py-0.5 rounded-full font-bold">待入帳</span>}
                 {order.status === 'synced' && <span className="text-xs bg-gray-200 text-gray-600 px-2 py-0.5 rounded-full">已完成</span>}
                 {order.status === 'void' && <span className="text-xs bg-red-600 text-white px-2 py-0.5 rounded-full font-bold">已作廢</span>}
               </div>
               <div className={`text-sm text-gray-600 font-medium ${order.status === 'void' ? 'line-through' : ''}`}>{order.itemsDesc || '一般消費'}</div>
            </div>
            <div className={`font-bold text-lg ${order.status === 'void' ? 'text-red-400 line-through' : 'text-gray-800'}`}>${order.amount}</div>
         </div>
       ))}
    </div>
  );
};

// --- Component: Bar View ---
const BarView = ({ user }) => {
  const [orders, setOrders] = useState([]);
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [prevScanningId, setPrevScanningId] = useState(null);
  const [showReport, setShowReport] = useState(false);
  
  useEffect(() => {
    const q = query(collection(db, 'artifacts', appId, 'public', 'data', 'orders'), orderBy('createdAt', 'desc'), limit(50));
    const unsub = onSnapshot(q, (snap) => setOrders(snap.docs.map(d => ({id:d.id, ...d.data()}))));
    return () => unsub();
  }, []);

  const scanningOrder = orders.find(o => o.status === 'scanning');
  const liveOrders = orders.filter(o => o.id !== scanningOrder?.id);

  useEffect(() => {
    if (scanningOrder && scanningOrder.id !== prevScanningId) {
        if (soundEnabled) playNotificationSound();
        setPrevScanningId(scanningOrder.id);
    }
  }, [scanningOrder, prevScanningId, soundEnabled]);

  const markAsSynced = async (id) => updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'orders', id), {status: 'synced'});
  
  const markAsVoid = async (id) => {
      if(confirm('確定要作廢此訂單嗎？\n此操作無法復原，且會從營收中扣除。')) {
          await updateDoc(doc(db, 'artifacts', appId, 'public', 'data', 'orders', id), {status: 'void'});
      }
  };

  return (
    <div className="flex flex-col h-screen bg-gray-100 max-w-2xl mx-auto shadow-2xl border-x border-gray-200 relative select-none">
      
      {showReport && <SalesReportModal onClose={() => setShowReport(false)} />}

      {/* --- POPUP: Scanning Modal --- */}
      {scanningOrder && (
        <div className="absolute inset-0 z-50 bg-gray-900/95 flex flex-col items-center justify-center p-4 animate-in zoom-in duration-300">
           <div className="bg-white p-6 rounded-2xl w-full max-w-sm shadow-2xl text-center">
              <div className="flex justify-between items-center mb-4 border-b pb-2">
                 <h3 className="text-xl font-bold text-gray-800 flex items-center"><Bell className="w-5 h-5 mr-2 animate-bounce text-purple-600"/>請掃描付款碼</h3>
                 <span className="bg-purple-100 text-purple-700 px-3 py-1 rounded-full text-xs font-bold animate-pulse">來自騎樓</span>
              </div>
              <div className="text-left bg-gray-50 p-3 rounded-lg mb-4 text-sm">
                 <p className="text-gray-500 mb-1">訂單內容：</p>
                 <p className="font-bold text-gray-800 text-lg">{scanningOrder.itemsDesc}</p>
                 <p className="text-right font-bold text-blue-600 text-xl mt-2">總計: ${scanningOrder.amount}</p>
              </div>
              <div className="bg-white border-4 border-red-500 rounded-xl p-2 mb-4 relative overflow-hidden">
                 {scanningOrder.paymentImage ? (
                    <img src={scanningOrder.paymentImage} alt="Customer Barcode" className="w-full h-auto object-contain max-h-64" style={{filter: 'contrast(1.2) brightness(1.1)'}} />
                 ) : (
                    <div className="h-32 flex items-center justify-center text-gray-400">圖片載入失敗</div>
                 )}
              </div>
              <button onClick={() => markAsSynced(scanningOrder.id)} className="w-full bg-green-600 hover:bg-green-700 text-white font-bold py-4 rounded-xl text-lg shadow-lg active:scale-95 transition">POS 已掃描完成</button>
              <button onClick={() => markAsVoid(scanningOrder.id)} className="mt-4 text-red-400 text-sm underline">訂單作廢</button>
           </div>
        </div>
      )}

      {/* Header */}
      <div className="bg-emerald-700 text-white p-4 shadow-md flex justify-between items-center z-10 shrink-0">
        <h2 className="font-bold text-xl flex items-center"><Zap className="w-6 h-6 mr-3"/> 吧台監控</h2>
        <div className="flex items-center gap-3">
           <button onClick={() => setShowReport(true)} className="bg-emerald-800/50 hover:bg-emerald-600 px-3 py-1.5 rounded-lg flex items-center text-sm font-bold transition">
              <PieChart size={16} className="mr-1"/> 報表
           </button>
           <button onClick={() => { setSoundEnabled(!soundEnabled); if(!soundEnabled) playNotificationSound(); }} className={`p-2 rounded-full transition ${soundEnabled ? 'bg-white/20' : 'bg-red-500/50'}`}>
              {soundEnabled ? <Volume2 size={20}/> : <VolumeX size={20}/>}
           </button>
        </div>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4 pb-20">
          {liveOrders.length === 0 && !scanningOrder ? (
            <div className="h-full flex flex-col items-center justify-center text-gray-400 opacity-60"><RefreshCw className="w-16 h-16 mb-4"/><p>無待處理交易</p></div>
          ) : (
            liveOrders.map(o => {
              const isCompleted = o.status === 'synced';
              const isVoid = o.status === 'void';
              
              if (isVoid) return null; // Optional: Hide void orders from main list to keep it clean, viewable in report or separate tab

              return (
              <div key={o.id} className={`relative overflow-hidden rounded-xl shadow-sm border-l-8 transition-all p-5 
                  ${isCompleted ? 'bg-gray-50 border-gray-300 opacity-70' : ''}
                  ${o.status==='paid'?'bg-white border-red-500 shadow-md':'bg-white border-yellow-400'}
              `}>
                <div className="flex justify-between items-center">
                  <div className="flex-1">
                    <div className="flex items-center space-x-2 mb-2">
                       <span className="text-xs font-mono text-gray-400 bg-gray-100 px-1 rounded">{o.createdAt?.toDate().toLocaleTimeString()||'同步中'}</span>
                       {o.status==='paid' && <span className="text-xs bg-red-100 text-red-600 px-2 py-0.5 rounded-full font-bold animate-pulse">顧客已掃店碼</span>}
                       {isCompleted && <span className="text-xs bg-gray-200 text-gray-600 px-2 py-0.5 rounded-full font-bold">已完成</span>}
                    </div>
                    <div className={`text-sm text-gray-600 mb-1 font-medium ${isCompleted ? 'text-gray-400' : ''}`}>{o.itemsDesc || '一般'}</div>
                    <div className={`text-4xl font-bold flex items-center ${isCompleted ? 'text-gray-400' : 'text-gray-800'}`}><DollarSign className="w-6 h-6 text-gray-400 mt-1"/>{o.amount}</div>
                  </div>
                  
                  {o.status==='paid' ? (
                      <button onClick={() => markAsSynced(o.id)} className="flex flex-col items-center justify-center bg-red-500 hover:bg-red-600 text-white w-24 h-24 rounded-2xl font-bold shadow-lg active:scale-95 ml-4">
                          <span className="text-xs opacity-80 mb-1">POS入帳</span><ArrowRight className="w-8 h-8"/><span className="text-xs font-mono mt-1">CLICK</span>
                      </button>
                  ) : isCompleted ? (
                      <div className="flex flex-col items-center justify-center ml-4 text-gray-400 gap-2">
                          <CheckCircle className="w-8 h-8"/>
                          {/* Void Button for completed orders */}
                          <button onClick={() => markAsVoid(o.id)} className="text-red-300 hover:text-red-500 p-1"><Ban size={20}/></button>
                      </div>
                  ) : (
                      <div className="px-6 animate-pulse"><Smartphone className="text-gray-300 w-10 h-10"/></div>
                  )}
                </div>
              </div>
            )})
        )}
      </div>
    </div>
  );
};

export default function App() {
  const [user, setUser] = useState(null);
  const [role, setRole] = useState(null);
  useEffect(() => {
    const init = async () => { if (typeof __initial_auth_token!=='undefined'&&__initial_auth_token) await signInWithCustomToken(auth, __initial_auth_token); else await signInAnonymously(auth); };
    init();
    return onAuthStateChanged(auth, setUser);
  }, []);
  if (!user) return <div className="flex items-center justify-center h-screen"><RefreshCw className="animate-spin text-gray-400"/></div>;
  if (!role) return <RoleSelection onSelectRole={setRole} />;
  return role === 'outside' ? <OutsideView user={user} /> : <BarView user={user} />;
}



