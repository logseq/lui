import assert from 'node:assert/strict'
import test from 'node:test'

const build=process.env.LUI_TEST_BUILD_DIR??'_build'
const modules=new URL(`../../../${build}/default/examples/components/web/lui-components-web/node_modules/`,import.meta.url)
const Agent=await import(new URL('lui.web.dom/shell/lui_web_agent.js',modules))

const target=flush=>({host:'web',runtime:{runtime_generation:{contents:3}},dispatch(){},flush})

test('Web answers lui-agent requests and turns a raising handler into a refusal',()=>{
  const hello=JSON.parse(Agent.answer(target(()=>{}),'{"op":"hello"}'))
  assert.equal(hello.ok,true)
  assert.equal(hello.protocol,'lui-agent')
  assert.equal(hello.host,'web')
  assert.equal(hello.generation,3)
  assert.deepEqual(JSON.parse(Agent.answer(target(()=>{}),'nope')).ok,false)
  const errors=[],error=console.error
  console.error=message=>errors.push(message)
  try {
    const refused=JSON.parse(Agent.answer(target(()=>{throw new Error('boom')}),'{"op":"tree"}'))
    assert.equal(refused.ok,false)
    assert.equal(refused.refused,true)
    assert.equal(refused.diagnostic.bridge,'web')
    assert.equal(refused.diagnostic.phase,'agent')
    assert.equal(refused.error,'boom')
    assert.equal(refused.diagnostic.message,'boom')
  } finally {
    console.error=error
  }
  assert.equal(errors.length,1)
})

test('Web dials only a loopback lui-agent socket named by the page URL',()=>{
  assert.equal(Agent.dial_url('?lui-agent=ws://127.0.0.1:49380'),'ws://127.0.0.1:49380')
  assert.equal(Agent.dial_url('?x=1&lui-agent=ws%3A%2F%2Flocalhost%3A9'),'ws://localhost:9')
  for(const search of ['','?lui-agent=','?lui-agent=ws://example.com:49380',
    '?lui-agent=ws://127.0.0.1.example.com:1','?lui-agent=ws://127.0.0.1:',
    '?lui-agent=ws://127.0.0.1:70000','?lui-agent=wss://127.0.0.1:1','?lui-agent=ws://127.0.0.1:1/path'])
    assert.equal(Agent.dial_url(search),undefined,search)
})
