import dev.lui.*;
public class LuiAndroidReview {
 static LuiPatchBatch batch(String json) { return LuiPatchBatch.Companion.parse(json); }
 static String setText(int gen,String value){return "{\"generation\":"+gen+",\"ops\":[{\"op\":\"set-prop\",\"id\":1,\"property\":\"text\",\"value\":"+value+"}]}";}
 public static void main(String[] args) throws Exception {
  for(String value:new String[]{"\"123\"","\"true\"","\"false\"","\"1.5\"","4294967296"}){
   LuiPatchOp.SetProp op=(LuiPatchOp.SetProp)batch(setText(1,value)).getOps().get(0);
   System.out.println("android_scalar input="+value+" decoded="+op.getValue());
  }
  LuiRetainedTree cycle=new LuiRetainedTree(new LuiExtensionRegistry());
  cycle.apply(batch("{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"column\"},{\"op\":\"insert-child\",\"parent\":1,\"child\":1,\"index\":0}]}"));
  System.out.println("android_self_cycle parent="+cycle.node(1).getParent()+" children="+cycle.node(1).getChildren());
  LuiRetainedTree store=new LuiRetainedTree(new LuiExtensionRegistry());
  store.apply(batch("{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"text\"}]}"));
  try {store.apply(batch("{\"generation\":2,\"ops\":[{\"op\":\"set-prop\",\"id\":99,\"property\":\"text\",\"value\":\"x\"}]}"));}catch(Exception e){}
  try {store.apply(batch(setText(3,"\"valid\"")));}catch(Exception e){System.out.println("android_after_rejection gen="+store.getGeneration()+" error="+e.getMessage());}
  for(int n:new int[]{1000,10000,50000}){
   store=new LuiRetainedTree(new LuiExtensionRegistry());StringBuilder init=new StringBuilder("{\"generation\":1,\"ops\":[");
   for(int i=1;i<=n;i++){if(i>1)init.append(',');init.append("{\"op\":\"create-node\",\"id\":").append(i).append(",\"kind\":\"text\"}");}
   init.append("]}");store.apply(batch(init.toString()));int gen=1;
   for(int i=0;i<20;i++)store.apply(batch(setText(++gen,"\"value\"")));
   long started=System.nanoTime();
   for(int i=0;i<100;i++)store.apply(batch(setText(++gen,"\"value\"")));
   System.out.printf("android_single_prop n=%d 100_updates_ms=%.2f%n",n,(System.nanoTime()-started)/1e6);
  }
 }
}
