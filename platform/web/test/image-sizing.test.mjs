import assert from 'node:assert/strict'
import test from 'node:test'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const [Store,Protocol,Schema,Tables,Props,Widgets]=await Promise.all([
  import(new URL('lui.web.dom/core/lui_web_store.js',modules)),
  import(new URL('lui/lui_protocol.js',modules)),
  import(new URL('lui/lui_wire_schema.js',modules)),
  import(new URL('melange/hashtbl.js',modules)),
  import(new URL('lui.web.dom/render/lui_web_props.js',modules)),
  import(new URL('lui.web.dom/widgets/lui_web_widgets.js',modules)),
])
const named=(values,nameOf,name)=>{
  for(let rest=values;rest;rest=rest.tl)if(nameOf(rest.hd)===name)return rest.hd
  throw Error(`Unknown schema value: ${name}`)
}
const kind=named(Schema.all_node_kinds,Schema.node_kind_name,'image')
const prop=name=>named(Schema.all_properties,Schema.property_name,name)
const list=values=>values.reduceRight((tl,hd)=>({hd,tl}),0)
const length=(value,reference)=>Number.parseFloat(value)*(value.endsWith('%')?reference/100:1)
const wire=(name,value)=>({TAG:typeof value==='string'?0:
  ['width','height','image'].includes(name)?2:3,_0:value})
const element=(children=[])=>{
  const styles=new Map(),attributes=new Map()
  return {styles,attributes,style:{setProperty:(key,value)=>styles.set(key,value)},
    children:{item:index=>children[index]??null,length:children.length},
    setAttribute:(key,value)=>attributes.set(key,value),
    removeAttribute:key=>attributes.delete(key),getAttribute:key=>attributes.get(key)??null}
}
function fixture(){
  const pixels=element(),box=element([pixels]),store=Store.create_store()
  const renderer={web_store:store,web_images:Tables.create(undefined,4)}
  let generation=0
  const apply=ops=>Store.apply_batch(store,()=>box,{generation:++generation,ops:list(ops)})
  apply([Protocol.create_node_op(1,kind),Protocol.set_prop_op(1,prop('url'),wire('url','https://example.test/cover.png'))])
  const set=entries=>{
    apply(entries.map(([name,value])=>Protocol.set_prop_op(1,prop(name),wire(name,value))))
    for(const [name,value] of entries)Props.apply_property(renderer,()=>{},1,kind,box,prop(name),wire(name,value))
  }
  const remove=(...names)=>{
    apply(names.map(name=>Protocol.remove_prop_op(1,prop(name))))
    for(const name of names)Props.remove_property(renderer,()=>{},1,kind,box,prop(name))
  }
  Widgets.update_image(renderer,1,box)
  return {pixels,box,renderer,set,remove,refresh:()=>Widgets.update_image(renderer,1,box)}
}

test('URL images retain intrinsic height with a width or horizontal frame',()=>{
  const f=fixture()
  f.set([['width',70]])
  assert.equal(f.pixels.styles.get('height'),'auto','An undimensioned height must follow the loaded image')
  assert.equal(f.pixels.styles.get('position'),'relative','Natural image pixels must participate in layout')
  assert.equal(f.pixels.styles.get('width'),'100%')
  f.remove('width');f.set([['container-relative-frame','horizontal']])
  assert.equal(f.pixels.styles.get('height'),'auto')
  assert.equal(f.pixels.styles.get('width'),'100%')
})

test('explicit image frames and later dimension removal retain the same pixels',()=>{
  const f=fixture(),pixels=f.pixels
  f.set([['width',70],['height',52]])
  assert.equal(pixels.styles.get('position')??'absolute','absolute')
  assert.equal(pixels.styles.get('width'),'100%')
  assert.equal(pixels.styles.get('height'),'100%')
  f.remove('height')
  assert.equal(pixels.styles.get('position'),'relative')
  assert.equal(pixels.styles.get('height'),'auto')
  f.set([['height',0]])
  assert.equal(pixels.styles.get('height'),'100%','An explicit zero is not an absent height')
  f.remove('width')
  assert.equal(pixels.styles.get('width'),'auto')
  assert.equal(pixels.styles.get('height'),'100%')
  assert.equal(f.pixels,pixels)
})

test('viewport dimensions and frame changes update intrinsic sizing',()=>{
  const f=fixture()
  f.set([['width-viewport',0.5],['height-viewport',0.4]])
  assert.equal(f.pixels.styles.get('position')??'absolute','absolute')
  f.remove('height-viewport')
  assert.equal(f.pixels.styles.get('height'),'auto')
  f.remove('width-viewport');f.set([['container-relative-frame','both']])
  assert.equal(f.pixels.styles.get('position'),'absolute')
  f.set([['container-relative-frame','vertical']])
  assert.equal(f.pixels.styles.get('width'),'auto')
  f.remove('container-relative-frame')
  assert.equal(f.pixels.styles.get('height'),'auto')
})

test('registered and cropped resources keep their source geometry',()=>{
  const f=fixture()
  Tables.replace(f.renderer.web_images,5,{web_image_url:'data:image/png;base64,fixture',web_image_width:192,web_image_height:144})
  f.set([['image',5],['width',70]])
  assert.equal(f.pixels.styles.get('height'),'auto')
  f.set([['source-x',16],['source-y',8],['source-width',80],['source-height',40]])
  assert.equal(f.box.styles.get('aspect-ratio'),'80 / 40')
  assert.equal(f.pixels.styles.get('position'),'absolute')
  f.set([['height',35]])
  assert.ok(Math.abs(length(f.pixels.styles.get('width'),70)-168)<1e-9)
  assert.ok(Math.abs(length(f.pixels.styles.get('height'),35)-126)<1e-9)
  f.remove('source-x','source-y','source-width','source-height')
  assert.equal(f.box.styles.get('aspect-ratio'),'')
  assert.equal(f.pixels.styles.get('width'),'100%')
  f.remove('height')
  assert.equal(f.pixels.styles.get('height'),'auto')
  f.remove('image')
  assert.equal(f.pixels.attributes.get('src'),'https://example.test/cover.png')
  assert.throws(()=>f.remove('url'),error=>error._1.includes('image requires image or url'))
})


test('authored auto image height retains intrinsic pixels and rejects other strings',()=>{
  const f=fixture()
  f.set([['width',70],['height','auto']])
  assert.equal(f.box.styles.get('height'),'auto')
  assert.equal(f.pixels.styles.get('height'),'auto')
  assert.equal(f.pixels.styles.get('position'),'relative')
  f.set([['height',52]])
  assert.equal(f.pixels.styles.get('position'),'absolute')
  f.set([['height','auto']])
  assert.equal(f.pixels.styles.get('position'),'relative')
  for(const value of ['inherit','AUTO','33.5px',''])
    assert.throws(()=>f.set([['height',value]]),`reject unsupported height ${value}`)
})

for(const registered of [false,true]) {
  test(`${registered?'registered':'URL'} image fitting updates pixels and restores stretch on removal`,()=>{
    const f=fixture(),pixels=f.pixels
    if(registered) {
      Tables.replace(f.renderer.web_images,5,{web_image_url:'data:image/png;base64,fixture',web_image_width:160,web_image_height:92})
      f.set([['image',5]])
    }
    f.set([['width',92],['height',63]])
    for(const [value,expected] of [['fill','cover'],['fit','contain'],['fill','cover']]) {
      f.set([['image-fit',value]])
      assert.equal(pixels.styles.get('object-fit'),expected,'Fitting applies to the bitmap, not its wrapper')
      f.refresh()
      assert.equal(pixels.styles.get('object-fit'),expected,'Source refresh preserves authored fitting')
      assert.equal(f.pixels,pixels,'Fit changes retain the decoded image element')
    }
    f.remove('image-fit')
    assert.equal(pixels.styles.get('object-fit'),'fill','Removal restores the existing stretch default')
  })
}
