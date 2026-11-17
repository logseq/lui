import assert from 'node:assert/strict'
import test from 'node:test'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const [Protocol,Widgets,Tables]=await Promise.all([
  import(new URL('lui/lui_protocol.js',modules)),
  import(new URL('lui.web.dom/widgets/lui_web_widgets.js',modules)),
  import(new URL('melange/hashtbl.js',modules)),
])

test('application icons resolve only requested names and preserve overrides',()=>{
  const requested=[],styles=new Map()
  const node={style:{setProperty:(name,value)=>styles.set(name,value)}}
  const renderer={web_inline_icons:Tables.create(undefined,4),web_app_icons:Protocol.String_map.add('override','./custom.svg',Protocol.String_map.empty),
    web_resolve_app_icon:name=>{requested.push(name);return name==='known'?{TAG:0,_0:'./known.svg'}:undefined}}
  Widgets.update_icon_name(renderer,1,node,'app:override')
  assert.deepEqual(requested,[])
  assert.match(styles.get('--lui-icon-image'),/custom\.svg/)
  Widgets.update_icon_name(renderer,1,node,'app:known')
  assert.deepEqual(requested,['known'])
  assert.match(styles.get('--lui-icon-image'),/known\.svg/)
  Widgets.update_icon_name(renderer,1,node,'app:missing')
  assert.deepEqual(requested,['known','missing'])
  assert.equal(styles.get('--lui-icon-image'),'url("./icons/missing.svg")')
  Widgets.update_icon_name(renderer,1,node,'search')
  assert.deepEqual(requested,['known','missing'])
  assert.match(styles.get('--lui-icon-image'),/icons\/search\.svg/)
})

const element=(tagName='svg',attributes=[],children=[])=>{
  const styles=new Map()
  return {tagName,namespaceURI:'http://www.w3.org/2000/svg',attributes,children,
    style:{setProperty:(name,value)=>styles.set(name,value),removeProperty:name=>styles.delete(name)},
    setAttribute(){},appendChild:child=>children.push(child),
    removeChild:child=>{children.splice(children.indexOf(child),1);return child}}
}

const list=items=>items.reduceRight((tl,hd)=>({hd,tl}),0)
const document={createElementNS:(_namespace,tag)=>element(tag)}
const svg=attributes=>({svg_view_box:'0 0 24 24',svg_filled:false,
  svg_shapes:list([[0,list(attributes)]])})

test('inline SVG shapes leave with their owning node without parsing documents',()=>{
  const parent=element('span')
  const renderer={web_app_icons:Protocol.String_map.empty,web_inline_icons:Tables.create(undefined,4),
    web_document:document,web_resolve_app_icon:()=>({TAG:1,_0:svg([[0,'M0 0h1']])})}
  Widgets.update_icon_name(renderer,1,parent,'app:first')
  assert.equal(parent.children.length,1)
  assert.equal(parent.children[0].children[0].tagName,'path')
  Widgets.update_icon_name(renderer,1,parent,'app:second')
  assert.equal(parent.children.length,1)
  Widgets.release_app_icon(renderer,1)
  Widgets.release_app_icon(renderer,1)
  assert.equal(parent.children.length,0)
  assert.equal(Tables.length(renderer.web_inline_icons),0)
})

test('dynamic SVG paints reject resource references',()=>{
  const fill=Array.from({length:29},(_,i)=>i).find(i=>Widgets.svg_attribute_name(i)==='fill')
  assert.throws(()=>Widgets.create_app_svg(document,svg([[fill,'url(https://example.test/icon)']])))
  assert.equal(Widgets.create_app_svg(document,svg([[fill,'currentColor']])).tagName,'svg')
})
