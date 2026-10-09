import { performance } from "node:perf_hooks";
import { pathToFileURL } from "node:url";
import { resolve } from "node:path";
const root = process.env.LUI_REVIEW_ROOT ?? process.cwd();
const base = pathToFileURL(resolve(root, "_build/default/examples/components/web/lui-components-web/node_modules") + "/").href;
const Store=await import(base+"lui.web.dom/core/lui_web_store.js");
const Protocol=await import(base+"lui/lui_protocol.js");
const Schema=await import(base+"lui/lui_wire_schema.js");
const list=a=>a.reduceRight((tl,hd)=>({hd,tl}),0);
const kind=name=>{for(let r=Schema.all_node_kinds;r;r=r.tl)if(Schema.node_kind_name(r.hd)===name)return r.hd;throw name;};
const prop=name=>{for(let r=Schema.all_properties;r;r=r.tl)if(Schema.property_name(r.hd)===name)return r.hd;throw name;};
const text=kind("text"), virtualList=kind("virtual-list"), textProp=prop("text");
const batch=(generation,ops)=>({generation,ops:list(ops)});
const str=s=>({TAG:0,_0:s});
const platform=()=>({});
for(const n of [1000,4000,8000]){
 const store=Store.create_store(),ops=[Protocol.create_node_op(1,virtualList)];
 for(let i=0;i<n;i++)ops.push(Protocol.create_node_op(i+2,text),Protocol.insert_child_op(1,i+2,i));
 const t=performance.now();Store.apply_batch(store,platform,batch(1,ops));
 console.log(`web_flat_mount n=${n} ms=${(performance.now()-t).toFixed(2)}`);
}
for(const n of [1000,10000,50000]){
 const store=Store.create_store(),ops=[];
 for(let i=1;i<=n;i++)ops.push(Protocol.create_node_op(i,text));
 Store.apply_batch(store,platform,batch(1,ops));let gen=1;
 for(let i=0;i<20;i++)Store.apply_batch(store,platform,batch(++gen,[Protocol.set_prop_op(1,textProp,str(String(gen)))]));
 const t=performance.now();
 for(let i=0;i<100;i++)Store.apply_batch(store,platform,batch(++gen,[Protocol.set_prop_op(1,textProp,str(String(gen)))]));
 console.log(`web_single_prop n=${n} 100_updates_ms=${(performance.now()-t).toFixed(2)}`);
}
const store=Store.create_store();Store.apply_batch(store,platform,batch(1,[Protocol.create_node_op(1,text),Protocol.set_prop_op(1,textProp,str("old"))]));
try{Store.apply_batch_with(store,platform,()=>false,batch(2,[Protocol.set_prop_op(1,textProp,str("new"))]));}catch{}
const retry=Store.apply_batch_with(store,platform,()=>true,batch(2,[Protocol.set_prop_op(1,textProp,str("new"))]));
console.log(`web_false_retry generation=${Store.generation(store)} accepted=${retry} text=${Store.property(store,1,textProp)._0}`);
